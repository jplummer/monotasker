import Foundation
import Observation
import SwiftUI

enum AppPhase: Equatable, Sendable {
  case bootstrapping
  case onboarding
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
  private var analytics: AnalyticsService?

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
  /// True while the "We found your Monotasker list!" onboarding toast is visible.
  var showAutoSelectedListToast: Bool = false
  /// True when resolveListAndLoad needs the list picker sheet to auto-present.
  var showListPickerSheet: Bool = false
  /// True during the fade-out/in transition when the user switches lists from the focused phase.
  var isListSwitching: Bool = false

  /// ID of the task currently in the undo window, filtered out of pool reloads.
  private var pendingTaskId: String? = nil
  private var undoTimerTask: Task<Void, Never>? = nil
  private var taskAddedToastTask: Task<Void, Never>? = nil
  private var autoSelectedToastTask: Task<Void, Never>? = nil
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
    if !skipInitialBootstrap {
      Task { await self.start() }
    }
  }

  /// Called from RootView's .task modifier after the first frame renders.
  /// Deferring TelemetryDeck init until here keeps it off the cold-launch critical path.
  func configureAnalytics(_ service: AnalyticsService) {
    analytics = service
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
    showListPickerSheet = true
    phase = .listSetup
  }

  func dismissAutoSelectedToast() {
    autoSelectedToastTask?.cancel()
    autoSelectedToastTask = nil
    showAutoSelectedListToast = false
  }

  func openListPickerFromToast() {
    analytics?.record("onboarding.change_tapped")
    dismissAutoSelectedToast()
    showListPickerSheet = true
  }

  func applyListChoice(_ summary: ReminderCalendarSummary) async {
    showListPickerSheet = false  // clear before phase changes
    if phase == .focused {
      isListSwitching = true
      try? await Task.sleep(for: .milliseconds(350))
    }
    selectionStore.selectedListIdentifier = summary.id
    activeListSummary = summary
    analytics?.record("list.switch")
    await loadPoolAndFocus()
    isListSwitching = false
  }

  func createDefaultList() async {
    await createReminderList(named: AppConfig.defaultListName)
  }

  /// Creates a new Reminders list with the given title and switches Monotasker to it.
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
    if phase == .focused {
      analytics?.record("onboarding.first_task_created")
    }
  }

  func cancelAdd() {
    showAddSheet = false
  }

  func confirmEdit(title: String, notes: String?) async {
    guard let task = currentTask else { return }
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let noteText = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let noteValue = noteText.isEmpty ? nil : noteText
    do {
      try reminders.updateReminder(id: task.id, title: trimmed, notes: noteValue)
      // Update in-memory immediately — avoids an async refetch and any intermediate-state flash.
      let updated = ReminderTask(id: task.id, title: trimmed, notes: noteValue, isCompleted: task.isCompleted)
      currentTask = updated
      pool = pool.map { $0.id == task.id ? updated : $0 }
    } catch RemindersServiceError.reminderNotFound {
      // Deleted externally between edit start and save — reload silently.
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
    } catch RemindersServiceError.reminderNotFound {
      // Task was already gone externally — treat as success and reload.
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

  private func showAutoSelectedListToastBriefly() {
    autoSelectedToastTask?.cancel()
    showAutoSelectedListToast = true
    autoSelectedToastTask = Task {
      try? await Task.sleep(for: .seconds(4))
      guard !Task.isCancelled else { return }
      showAutoSelectedListToast = false
    }
  }

  /// Sends the deferred action to EventKit. Does not reload the pool.
  private func sendToEventKit(_ action: UndoableAction) async {
    do {
      switch action {
      case .deletion(let task): try reminders.deleteReminder(id: task.id)
      case .completion(let task): try reminders.completeReminder(id: task.id)
      }
    } catch RemindersServiceError.reminderNotFound {
      // Already gone externally — the pool reload after this call will catch up.
      return
    } catch {
      analytics?.record("error.critical", parameters: ["site": "sendToEventKit"])
      userMessage = error.localizedDescription
    }
  }

  // MARK: - Onboarding

  func recordOnboardingImpression() {
    analytics?.record("onboarding.impression")
  }

  /// Called from OnboardingView when the user taps "Connect my Reminders".
  func connectReminders() async {
    analytics?.record("onboarding.cta_tapped")
    switch reminders.currentAuthorization() {
    case .undetermined:
      do {
        let ok = try await reminders.requestFullAccess()
        if ok {
          analytics?.record("permission.outcome", parameters: ["result": "granted"])
          await resolveListAndLoad(fromOnboarding: true)
        } else {
          analytics?.record("permission.outcome", parameters: ["result": "denied"])
          phase = .permissionDenied
        }
      } catch {
        analytics?.record("permission.outcome", parameters: ["result": "error"])
        phase = .permissionDenied
      }
    case .fullAccess:
      await resolveListAndLoad(fromOnboarding: true)
    case .denied, .writeOnly:
      analytics?.record("permission.outcome", parameters: ["result": "denied"])
      phase = .permissionDenied
    }
  }

  // MARK: - Private

  private func bootstrap() async {
    let bt0 = Date()
    print("[TIMING] bootstrap() start: +\(String(format: "%.3f", bt0.timeIntervalSince(MonotaskerTiming.t0)))s")
    phase = .bootstrapping
    userMessage = nil

    // Fast path: no stored list means the user has never completed onboarding.
    // Skip EKEventStore.authorizationStatus() — even this class method appears to wake
    // the Calendar/Reminders daemon via XPC, causing a multi-second cold-start delay
    // on first install when the daemon is not yet running.
    guard selectionStore.selectedListIdentifier != nil else {
      phase = .onboarding
      print("[TIMING] bootstrap() → .onboarding (fast path): +\(String(format: "%.3f", Date().timeIntervalSince(MonotaskerTiming.t0)))s")
      // Pre-warm the daemon in the background while the user reads the onboarding card.
      // By the time they tap the checkbox, the XPC connection is established and the
      // system permission dialog appears without the cold-start delay.
      let svc = reminders
      Task.detached(priority: .background) { _ = svc.currentAuthorization() }
      return
    }

    print("[TIMING] bootstrap() calling authorizationStatus: +\(String(format: "%.3f", Date().timeIntervalSince(MonotaskerTiming.t0)))s")
    let authorization = reminders.currentAuthorization()
    print("[TIMING] bootstrap() authorizationStatus done (\(authorization)): +\(String(format: "%.3f", Date().timeIntervalSince(MonotaskerTiming.t0)))s")
    switch authorization {
    case .undetermined, .denied, .writeOnly:
      phase = .onboarding
    case .fullAccess:
      // Fetch immediately — bootstrap card stays visible until data is ready, no artificial delay.
      await resolveListAndLoad()
    }
  }

  private func startEventStoreObservationIfNeeded() {
    guard observationTask == nil else { return }
    observationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for await _ in self.reminders.eventStoreChanges() {
        await self.reloadForExternalChange()
      }
    }
  }

  private func resolveListAndLoad(fromOnboarding: Bool = false) async {
    startEventStoreObservationIfNeeded()
    if let storedId = selectionStore.selectedListIdentifier,
       let summary = reminders.calendar(withIdentifier: storedId) {
      activeListSummary = summary
      if fromOnboarding {
        analytics?.record("onboarding.list_auto_selected")
        showAutoSelectedListToastBriefly()
      }
      await loadPoolAndFocus()
      if fromOnboarding { offsetPoolColorFromOnboarding() }
      if fromOnboarding && (phase == .focused || phase == .emptyList) {
        analytics?.record("onboarding.complete")
      }
      return
    }
    if let summary = reminders.firstCalendar(named: AppConfig.defaultListName) {
      selectionStore.selectedListIdentifier = summary.id
      activeListSummary = summary
      if fromOnboarding {
        analytics?.record("onboarding.list_auto_selected")
        showAutoSelectedListToastBriefly()
      }
      await loadPoolAndFocus()
      if fromOnboarding { offsetPoolColorFromOnboarding() }
      if fromOnboarding && (phase == .focused || phase == .emptyList) {
        analytics?.record("onboarding.complete")
      }
      return
    }
    if fromOnboarding {
      analytics?.record("onboarding.list_picker_opened")
    }
    showListPickerSheet = true
    phase = .listSetup
  }

  private func loadPoolAndFocus() async {
    guard let listId = activeListSummary?.id ?? selectionStore.selectedListIdentifier else {
      showListPickerSheet = true
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
      showListPickerSheet = true
      phase = .listSetup
    }
  }

  /// Ensures the first task shown after onboarding doesn't share colorIndex 0 with the
  /// onboarding card. If the focused task landed at pool[0], swap it to pool[1].
  private func offsetPoolColorFromOnboarding() {
    guard pool.count > 1, let taskId = currentTask?.id, pool[0].id == taskId else { return }
    pool.swapAt(0, 1)
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
