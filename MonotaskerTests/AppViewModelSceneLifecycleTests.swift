import XCTest
@testable import Monotasker

@MainActor
final class AppViewModelSceneLifecycleTests: XCTestCase {

  private func makeStore(listId: String = "cal-1", reminderId: String? = nil) -> SelectionStore {
    let suite = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SelectionStore(defaults: defaults)
    store.selectedListIdentifier = listId
    if let reminderId { store.setReminderID(reminderId, forList: listId) }
    return store
  }

  private func makeVM(mock: MockRemindersService, store: SelectionStore) -> AppViewModel {
    AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
  }

  // MARK: - Recovery: permission screen → granted

  func testSceneActiveRecoversFocusedFromPermissionDenied() async {
    let task = ReminderTask(id: "r-1", title: "Task", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .denied,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .onboarding)

    // Simulate user going to Settings and granting Full Access, then returning.
    mock.setAuthorization(.fullAccess)
    // bootstrap() fast path skipped — stored list exists, so the onboarding phase
    // here actually means we had a stored list with denied auth.
    // Set phase to permissionDenied to simulate the connectReminders denial path.
    vm.phase = .permissionDenied
    await vm.sceneDidBecomeActive()

    XCTAssertEqual(vm.phase, .focused)
    XCTAssertEqual(vm.currentTask?.id, "r-1")
  }

  func testSceneActiveRecoversFocusedFromOnboarding() async {
    let task = ReminderTask(id: "r-1", title: "Task", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .denied,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .onboarding)

    mock.setAuthorization(.fullAccess)
    await vm.sceneDidBecomeActive()

    XCTAssertEqual(vm.phase, .focused)
    XCTAssertEqual(vm.currentTask?.id, "r-1")
  }

  // MARK: - Revocation: app in use → denied

  func testSceneActiveGoesToPermissionDeniedWhenRevokedWhileFocused() async {
    let task = ReminderTask(id: "r-1", title: "Task", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .focused)

    mock.setAuthorization(.denied)
    await vm.sceneDidBecomeActive()

    XCTAssertEqual(vm.phase, .permissionDenied)
  }

  func testSceneActiveGoesToPermissionDeniedWhenWriteOnlyRevokedWhileFocused() async {
    let task = ReminderTask(id: "r-1", title: "Task", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .focused)

    mock.setAuthorization(.writeOnly)
    await vm.sceneDidBecomeActive()

    XCTAssertEqual(vm.phase, .permissionDenied)
  }

  func testSceneActiveGoesToPermissionDeniedWhenRevokedWhileEmptyList() async {
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": []]
    )
    let store = makeStore()
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .emptyList)

    mock.setAuthorization(.denied)
    await vm.sceneDidBecomeActive()

    XCTAssertEqual(vm.phase, .permissionDenied)
  }

  // MARK: - No-ops: no unnecessary reloads

  func testSceneActiveNoopWhenAlreadyFocused() async {
    let task = ReminderTask(id: "r-1", title: "Task", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .focused)
    let fetchCountBefore = mock.fetchCallCount

    await vm.sceneDidBecomeActive()

    XCTAssertEqual(vm.phase, .focused)
    XCTAssertEqual(mock.fetchCallCount, fetchCountBefore, "Should not re-fetch pool on normal foreground return")
  }

  func testSceneActiveNoopWhenPermissionStillDenied() async {
    let mock = MockRemindersService(authorization: .denied)
    let store = makeStore()
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    vm.phase = .permissionDenied

    await vm.sceneDidBecomeActive()

    XCTAssertEqual(vm.phase, .permissionDenied)
  }

  // MARK: - Regression: reminderNotFound on action → silent reload

  func testCompleteReminderNotFoundReloadsPoolSilently() async throws {
    let task = ReminderTask(id: "r-1", title: "Task", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .focused)

    // Remove the task externally so completeReminder throws reminderNotFound.
    try mock.deleteReminder(id: "r-1")
    await vm.beginComplete()

    XCTAssertNil(vm.userMessage, "reminderNotFound should not surface an alert")
    XCTAssertEqual(vm.phase, .emptyList)
  }

  func testDeleteReminderNotFoundReloadsPoolSilently() async throws {
    let task = ReminderTask(id: "r-1", title: "Task", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .focused)

    try mock.deleteReminder(id: "r-1")
    await vm.beginDelete()

    XCTAssertNil(vm.userMessage, "reminderNotFound should not surface an alert")
    XCTAssertEqual(vm.phase, .emptyList)
  }

  func testEditReminderNotFoundReloadsPoolSilently() async throws {
    let task = ReminderTask(id: "r-1", title: "Task", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .focused)

    try mock.deleteReminder(id: "r-1")
    await vm.confirmEdit(title: "New title", notes: nil)

    XCTAssertNil(vm.userMessage, "reminderNotFound should not surface an alert")
    XCTAssertEqual(vm.phase, .emptyList)
  }
}
