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

@MainActor
@Observable
final class AppViewModel {
  private let reminders: RemindersService
  private let selectionStore: SelectionStore
  private var selectionPolicy: UniformRandomTopLevelPolicy

  var phase: AppPhase = .bootstrapping
  var userMessage: String?
  var activeListSummary: ReminderCalendarSummary?
  var pool: [ReminderTask] = []
  var currentTask: ReminderTask?
  var showAddSheet = false
  var showOnlyOneTaskAlert = false
  /// Captured when an add flow starts; drives the surfacing rule (0/1 vs 2+).
  var poolSizeWhenAddOpened = 0

  private var observationTask: Task<Void, Never>?

  init(
    reminders: RemindersService,
    selectionStore: SelectionStore,
    selectionPolicy: UniformRandomTopLevelPolicy = UniformRandomTopLevelPolicy(),
    skipInitialBootstrap: Bool = false
  ) {
    self.reminders = reminders
    self.selectionStore = selectionStore
    self.selectionPolicy = selectionPolicy
    observationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for await _ in self.reminders.eventStoreChanges() {
        await self.reloadForExternalChange()
      }
    }
    if !skipInitialBootstrap {
      Task { await self.bootstrap() }
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
    selectionStore.selectedReminderIdentifier = task.id
    if result.onlyOneInPool {
      showOnlyOneTaskAlert = true
    }
  }

  func completeCurrent() async {
    guard let task = currentTask else { return }
    do {
      try reminders.completeReminder(id: task.id)
      selectionStore.clearReminderSelection()
      await loadPoolAndFocus()
    } catch {
      userMessage = error.localizedDescription
    }
  }

  func deleteCurrent() async {
    guard let task = currentTask else { return }
    do {
      try reminders.deleteReminder(id: task.id)
      selectionStore.clearReminderSelection()
      await loadPoolAndFocus()
    } catch {
      userMessage = error.localizedDescription
    }
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

  // MARK: - Private

  private func bootstrap() async {
    phase = .bootstrapping
    userMessage = nil
    switch reminders.currentAuthorization() {
    case .undetermined:
      do {
        let ok = try await reminders.requestFullAccess()
        if !ok {
          phase = .permissionDenied
          return
        }
      } catch {
        phase = .permissionDenied
        userMessage = error.localizedDescription
        return
      }
      await resolveListAndLoad()
    case .fullAccess:
      await resolveListAndLoad()
    case .denied, .writeOnly:
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
      let newPool = try await reminders.fetchIncompleteTopLevel(calendarId: listId)
      pool = newPool
      if newPool.isEmpty {
        selectionStore.clearReminderSelection()
        currentTask = nil
        phase = .emptyList
        return
      }
      if let rid = selectionStore.selectedReminderIdentifier,
         let existing = newPool.first(where: { $0.id == rid }) {
        currentTask = existing
        phase = .focused
        return
      }
      let result = selectionPolicy.pick(from: newPool, excluding: nil)
      if let task = result.task {
        currentTask = task
        selectionStore.selectedReminderIdentifier = task.id
        phase = .focused
      }
    } catch {
      userMessage = error.localizedDescription
      phase = .listSetup
    }
  }

  private func loadPoolAfterAdd(createdId: String, priorPoolSize: Int) async {
    guard let listId = activeListSummary?.id else { return }
    do {
      let newPool = try await reminders.fetchIncompleteTopLevel(calendarId: listId)
      pool = newPool
      if newPool.isEmpty {
        selectionStore.clearReminderSelection()
        currentTask = nil
        phase = .emptyList
        return
      }
      if priorPoolSize <= 1 {
        if let t = newPool.first(where: { $0.id == createdId }) {
          currentTask = t
          selectionStore.selectedReminderIdentifier = createdId
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
    guard reminders.currentAuthorization() == .fullAccess else { return }
    guard activeListSummary != nil || selectionStore.selectedListIdentifier != nil else { return }
    await loadPoolAndFocus()
  }
}
