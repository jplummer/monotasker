import Foundation
import Observation
import SwiftUI

enum AppPhase: Equatable, Sendable {
  case bootstrapping
  case permissionDenied
  case listSetup
  case emptyList
  case focused
}

enum UndoableAction: Sendable {
  case deletion(task: ReminderTask)
  case completion(task: ReminderTask)

  var toastMessage: String {
    switch self {
    case .deletion: "Task deleted."
    case .completion: "Completed!"
    }
  }
}

@MainActor
@Observable
final class AppViewModel {
  private let reminders: RemindersService
  private let selectionStore: SelectionStore
  private var selectionPolicy: UniformRandomTopLevelPolicy
  private let analytics: AnalyticsService?

  var phase: AppPhase = .bootstrapping
  var userMessage: String?
  var activeListSummary: ReminderCalendarSummary?
  var pool: [ReminderTask] = []
  var currentTask: ReminderTask?
  var showAddSheet = false
  var showOnlyOneTaskAlert = false
  /// Captured when an add flow starts; drives the surfacing rule (0/1 vs 2+).
  var poolSizeWhenAddOpened = 0
  /// Non-nil while the undo window is open. The action has NOT been sent to EventKit yet.
  var pendingUndo: UndoableAction? = nil
  /// True while the "Task added" info toast is visible.
  var showTaskAddedToast: Bool = false

  /// ID of the task currently in the undo window, filtered out of pool reloads.
  private var pendingTaskId: String? = nil
  private var undoTimerTask: Task<Void, Never>? = nil
  private var taskAddedToastTask: Task<Void, Never>? = nil
  private var externalChangeDebounceTask: Task<Void, Never>? = nil

  private var observationTask: Task<Void, Never>?
  private let undoDelay: Duration
  private let externalChangeDebounce: Duration

  init(
    reminders: RemindersService,
    selectionStore: SelectionStore,
    selectionPolicy: UniformRandomTopLevelPolicy = UniformRandomTopLevelPolicy(),
    analytics: AnalyticsService? = nil,
    undoDelay: Duration = .seconds(4),
    externalChangeDebounce: Duration = .milliseconds(500),
    skipInitialBootstrap: Bool = false
  ) {
    self.undoDelay = undoDelay
    self.externalChangeDebounce = externalChangeDebounce
    self.reminders = reminders
    self.selectionStore = selectionStore
    self.selectionPolicy = selectionPolicy
    self.analytics = analytics
    observationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for await _ in self.reminders.eventStoreChanges() {
        await self.reloadForExternalChange()
      }
    }
    if !skipInitialBootstrap {
      Task { await self.start() }
    }
  }

  /// Entry point for previews and tests when `skipInitialBootstrap` was `true`.
  func start() async {
    await bootstrap()
  }

  // MARK: - Setup / permissions

  func calendarsForSetup() -> [ReminderCalendarSummary] {
    reminders.reminderCalendars()
  }

  func refreshAfterSettings() async {
    await bootstrap()
  }

  func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  func openListSetup() {
    phase = .listSetup
  }

  func applyListChoice(_ summary: ReminderCalendarSummary) async {
    selectionStore.selectedListIdentifier = summary.id
    activeListSummary = summary
    analytics?.record("list.switch")
    await loadPoolAndFocus()
  }

  func createDefaultList() async {
    await createReminderList(named: AppConfig.defaultListName)
  }

  /// Creates a new Reminders list with the given title and switches Monotask to it.
  func createReminderList(named title: String) async {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    do {
      let summary = try reminders.createReminderList(title: trimmed)
      await applyListChoice(summary)
    } catch {
      userMessage = error.localizedDescription
    }
  }

  // MARK: - Focus actions

  func beginAdd() {
    poolSizeWhenAddOpened = pool.count
    showAddSheet = true
  }

  func beginAddFromOnlyOneAlert() {
    showOnlyOneTaskAlert = false
    poolSizeWhenAddOpened = pool.count
    showAddSheet = true
  }

  func dismissOnlyOneTaskAlert() {
    showOnlyOneTaskAlert = false
  }

  func reroll() async {
    guard let current = currentTask else { return }
    let result = selectionPolicy.pick(from: pool, excluding: current.id)
    guard let task = result.task else { return }
    currentTask = task
    guard let listId = activeListSummary?.id else { return }
    selectionStore.setReminderID(task.id, forList: listId)
    analytics?.record("task.reroll")
    if result.onlyOneInPool {
      showOnlyOneTaskAlert = true
    }
  }

  /// Completes the current task with a 4-second undo window (skipped when only one task remains).
  func beginComplete() async {
    guard let task = currentTask else { return }
    guard pool.count > 1 else {
      await executeImmediately(.completion(task: task))
      return
    }
    await cancelAndCommitPending()
    pendingTaskId = task.id
    await loadPoolAndFocus()
    pendingUndo = .completion(task: task)
    analytics?.record("task.complete")
    startUndoTimer()
  }

  /// Deletes the current task with a 4-second undo window (skipped when only one task remains).
  func beginDelete() async {
    guard let task = currentTask else { return }
    guard pool.count > 1 else {
      await executeImmediately(.deletion(task: task))
      return
    }
    await cancelAndCommitPending()
    pendingTaskId = task.id
    await loadPoolAndFocus()
    pendingUndo = .deletion(task: task)
    analytics?.record("task.delete")
    startUndoTimer()
  }

  /// Cancels the pending action and restores the task to the pool.
  func undoPendingAction() async {
    undoTimerTask?.cancel()
    undoTimerTask = nil
    guard let undo = pendingUndo else { return }
    analytics?.record("task.undo", parameters: ["action": undo.toastMessage])
    let task: ReminderTask = switch undo {
    case .deletion(let t): t
    case .completion(let t): t
    }
    pendingUndo = nil
    pendingTaskId = nil
    if let listId = activeListSummary?.id {
      // activeListSummary is always set when phase == .focused (the only state where undo is possible).
      selectionStore.setReminderID(task.id, forList: listId)
    }
    await loadPoolAndFocus()
  }

  func confirmAdd(title: String, notes: String?) async {
    guard let listId = activeListSummary?.id else { return }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let prior = poolSizeWhenAddOpened
    do {
      let noteText = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let noteValue = noteText.isEmpty ? nil : noteText
      let created = try reminders.createReminder(
        title: trimmed,
        notes: noteValue,
        calendarId: listId
      )
      showAddSheet = false
      await loadPoolAfterAdd(createdId: created.id, priorPoolSize: prior)
      analytics?.record("task.add")
      showTaskAddedToastBriefly()
    } catch {
      userMessage = error.localizedDescription
    }
  }

  func addFromEmpty(title: String, notes: String?) async {
    poolSizeWhenAddOpened = 0
    await confirmAdd(title: title, notes: notes)
  }

  func cancelAdd() {
    showAddSheet = false
  }

  func confirmEdit(title: String, notes: String?) async {
    guard let task = currentTask else { return }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    do {
      let noteText = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let noteValue = noteText.isEmpty ? nil : noteText
      try reminders.updateReminder(id: task.id, title: trimmed, notes: noteValue)
      await loadPoolAndFocus()
    } catch {
      userMessage = error.localizedDescription
    }
  }

  // MARK: - Undo internals

  private func startUndoTimer() {
    undoTimerTask = Task {
      try? await Task.sleep(for: undoDelay)
      guard !Task.isCancelled else { return }
      await commitPending()
    }
  }

  private func commitPending() async {
    guard let action = pendingUndo else { return }
    pendingUndo = nil
    pendingTaskId = nil
    undoTimerTask = nil
    await sendToEventKit(action)
  }

  /// If a previous undo window is open, commit it immediately before starting a new one.
  private func cancelAndCommitPending() async {
    undoTimerTask?.cancel()
    undoTimerTask = nil
    if let action = pendingUndo {
      pendingUndo = nil
      pendingTaskId = nil
      await sendToEventKit(action)
    }
  }

  /// Execute an action immediately with no undo window (used for single-task pool).
  private func executeImmediately(_ action: UndoableAction) async {
    let task: ReminderTask = switch action {
    case .deletion(let t): t
    case .completion(let t): t
    }
    do {
      switch action {
      case .deletion: try reminders.deleteReminder(id: task.id)
      case .completion: try reminders.completeReminder(id: task.id)
      }
      await loadPoolAndFocus()
    } catch {
      analytics?.record("error.critical", parameters: ["site": "executeImmediately"])
      userMessage = error.localizedDescription
    }
  }

  private func showTaskAddedToastBriefly() {
    taskAddedToastTask?.cancel()
    showTaskAddedToast = true
    taskAddedToastTask = Task {
      try? await Task.sleep(for: .seconds(2.5))
      guard !Task.isCancelled else { return }
      showTaskAddedToast = false
    }
  }

  /// Sends the deferred action to EventKit. Does not reload the pool.
  private func sendToEventKit(_ action: UndoableAction) async {
    do {
      switch action {
      case .deletion(let task): try reminders.deleteReminder(id: task.id)
      case .completion(let task): try reminders.completeReminder(id: task.id)
      }
    } catch {
      analytics?.record("error.critical", parameters: ["site": "sendToEventKit"])
      userMessage = error.localizedDescription
    }
  }

  // MARK: - Private

  private func bootstrap() async {
    phase = .bootstrapping
    userMessage = nil
    switch reminders.currentAuthorization() {
    case .undetermined:
      do {
        let ok = try await reminders.requestFullAccess()
        if !ok {
          analytics?.record("permission.outcome", parameters: ["result": "denied"])
          phase = .permissionDenied
          return
        }
      } catch {
        analytics?.record("permission.outcome", parameters: ["result": "error"])
        phase = .permissionDenied
        userMessage = error.localizedDescription
        return
      }
      analytics?.record("permission.outcome", parameters: ["result": "granted"])
      await resolveListAndLoad()
    case .fullAccess:
      await resolveListAndLoad()
    case .denied, .writeOnly:
      analytics?.record("permission.outcome", parameters: ["result": "denied"])
      phase = .permissionDenied
    }
  }

  private func resolveListAndLoad() async {
    if let storedId = selectionStore.selectedListIdentifier,
       let summary = reminders.calendar(withIdentifier: storedId) {
      activeListSummary = summary
      await loadPoolAndFocus()
      return
    }
    if let summary = reminders.firstCalendar(named: AppConfig.defaultListName) {
      selectionStore.selectedListIdentifier = summary.id
      activeListSummary = summary
      await loadPoolAndFocus()
      return
    }
    phase = .listSetup
  }

  private func loadPoolAndFocus() async {
    guard let listId = activeListSummary?.id ?? selectionStore.selectedListIdentifier else {
      phase = .listSetup
      return
    }
    if activeListSummary == nil, let s = reminders.calendar(withIdentifier: listId) {
      activeListSummary = s
    }
    do {
      let raw = try await reminders.fetchIncompleteTopLevel(calendarId: listId)
      // Hide any task currently in the undo window — it hasn't been sent to EventKit yet.
      let newPool = pendingTaskId.map { id in raw.filter { $0.id != id } } ?? raw
      pool = newPool
      if newPool.isEmpty {
        selectionStore.clearReminderID(forList: listId)
        currentTask = nil
        phase = .emptyList
        return
      }
      if let rid = selectionStore.reminderID(forList: listId),
         let existing = newPool.first(where: { $0.id == rid }) {
        currentTask = existing
        phase = .focused
        return
      }
      let result = selectionPolicy.pick(from: newPool, excluding: nil)
      if let task = result.task {
        currentTask = task
        selectionStore.setReminderID(task.id, forList: listId)
        phase = .focused
      }
    } catch {
      analytics?.record("error.critical", parameters: ["site": "loadPoolAndFocus"])
      userMessage = error.localizedDescription
      phase = .listSetup
    }
  }

  private func loadPoolAfterAdd(createdId: String, priorPoolSize: Int) async {
    guard let listId = activeListSummary?.id else { return }
    do {
      let raw = try await reminders.fetchIncompleteTopLevel(calendarId: listId)
      let newPool = pendingTaskId.map { id in raw.filter { $0.id != id } } ?? raw
      pool = newPool
      if newPool.isEmpty {
        selectionStore.clearReminderID(forList: listId)
        currentTask = nil
        phase = .emptyList
        return
      }
      if priorPoolSize <= 1 {
        if let t = newPool.first(where: { $0.id == createdId }) {
          currentTask = t
          selectionStore.setReminderID(createdId, forList: listId)
          phase = .focused
          return
        }
      }
      await loadPoolAndFocus()
    } catch {
      userMessage = error.localizedDescription
    }
  }

  private func reloadForExternalChange() async {
    // Debounce: cancel any in-flight reload and restart the timer. This coalesces rapid
    // EKEventStoreChanged bursts (e.g. iCloud sync) into a single pool fetch.
    externalChangeDebounceTask?.cancel()
    externalChangeDebounceTask = Task {
      try? await Task.sleep(for: externalChangeDebounce)
      guard !Task.isCancelled else { return }
      guard reminders.currentAuthorization() == .fullAccess else { return }
      guard activeListSummary != nil || selectionStore.selectedListIdentifier != nil else { return }
      await loadPoolAndFocus()
    }
  }
}
