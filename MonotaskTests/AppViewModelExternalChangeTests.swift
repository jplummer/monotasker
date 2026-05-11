import XCTest
@testable import Monotask

@MainActor
final class AppViewModelExternalChangeTests: XCTestCase {

  private func makeStore(listId: String = "cal-1", reminderId: String? = nil) -> SelectionStore {
    let suite = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SelectionStore(defaults: defaults)
    store.selectedListIdentifier = listId
    if let reminderId { store.setReminderID(reminderId, forList: listId) }
    return store
  }

  func testExternalChangeReloadsPoolWhileFocused() async throws {
    var tasks: [ReminderTask] = [
      ReminderTask(id: "r-1", title: "Original", isCompleted: false)
    ]
    let mock = MockRemindersService(
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotask")],
      reminders: ["cal-1": tasks]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      externalChangeDebounce: .milliseconds(0),
      skipInitialBootstrap: true
    )
    await vm.start()
    XCTAssertEqual(vm.pool.count, 1)

    // Add a second task directly to mock (simulates Reminders.app edit) and fire change
    try mock.createReminder(title: "Added externally", notes: nil, calendarId: "cal-1")
    // emitChange is called inside createReminder; allow the observation task to process it
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(vm.pool.count, 2)
    XCTAssertTrue(vm.pool.contains { $0.title == "Added externally" })
  }

  func testExternalChangeUpdatesCurrentTaskDataIfChanged() async throws {
    let mock = MockRemindersService(
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotask")],
      reminders: ["cal-1": [ReminderTask(id: "r-1", title: "Old title", isCompleted: false)]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      externalChangeDebounce: .milliseconds(0),
      skipInitialBootstrap: true
    )
    await vm.start()
    XCTAssertEqual(vm.currentTask?.title, "Old title")

    try mock.updateReminder(id: "r-1", title: "Updated title", notes: nil)
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(vm.currentTask?.title, "Updated title")
  }

  func testExternalChangeIgnoredWhenActiveListSummaryIsNil() async throws {
    let mock = MockRemindersService(
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotask")],
      reminders: ["cal-1": []]
    )
    // Store with no list ID so activeListSummary stays nil
    let suite = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SelectionStore(defaults: defaults)

    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      externalChangeDebounce: .milliseconds(0),
      skipInitialBootstrap: true
    )
    // Don't call start() — activeListSummary stays nil

    // Emit a change; the VM should silently ignore it (no crash, no phase change)
    _ = try? mock.createReminder(title: "trigger", notes: nil, calendarId: "cal-1")
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(vm.phase, .bootstrapping)
    XCTAssertNil(vm.activeListSummary)
  }

  func testExternalChangeIgnoredWhenPermissionNotFullAccess() async throws {
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotask")],
      reminders: ["cal-1": [ReminderTask(id: "r-1", title: "Task", isCompleted: false)]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      externalChangeDebounce: .milliseconds(0),
      skipInitialBootstrap: true
    )
    await vm.start()

    // Revoke permission then trigger a change
    mock.setAuthorization(.denied)
    try mock.createReminder(title: "Should not appear", notes: nil, calendarId: "cal-1")
    try await Task.sleep(for: .milliseconds(50))

    // Pool count should not have grown (reload was skipped)
    XCTAssertEqual(vm.pool.count, 1)
  }
}
