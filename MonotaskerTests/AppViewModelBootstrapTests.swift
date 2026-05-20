import XCTest
@testable import Monotasker

@MainActor
final class AppViewModelBootstrapTests: XCTestCase {

  // MARK: - Helpers

  private func makeStore(listId: String? = nil, reminderId: String? = nil) -> SelectionStore {
    let suite = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SelectionStore(defaults: defaults)
    store.selectedListIdentifier = listId
    if let listId, let reminderId {
      store.setReminderID(reminderId, forList: listId)
    }
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

  // MARK: - Happy path

  func testFullAccessPersistedListNonEmptyPool() async {
    let task = ReminderTask(id: "r-1", title: "Do thing", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(listId: "cal-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .focused)
    XCTAssertEqual(vm.currentTask?.id, "r-1")
    XCTAssertEqual(store.reminderID(forList: "cal-1"), "r-1")
  }

  func testFullAccessPersistedListResumesStoredReminder() async {
    let r1 = ReminderTask(id: "r-1", title: "A", isCompleted: false)
    let r2 = ReminderTask(id: "r-2", title: "B", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [r1, r2]]
    )
    let store = makeStore(listId: "cal-1", reminderId: "r-2")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .focused)
    XCTAssertEqual(vm.currentTask?.id, "r-2")
  }

  // MARK: - List resolution fallback

  func testStaleListIdFallsBackToNameMatch() async {
    let task = ReminderTask(id: "r-1", title: "Do thing", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-real", title: "Monotasker")],
      reminders: ["cal-real": [task]]
    )
    let store = makeStore(listId: "cal-stale")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .focused)
    XCTAssertEqual(vm.currentTask?.id, "r-1")
  }

  func testNoPersistedListGoesToOnboarding() async {
    // No stored list → fast path straight to onboarding (skips EKEventStore access).
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Work")],
      reminders: ["cal-1": []]
    )
    let store = makeStore()
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .onboarding)
  }

  func testStaleListIdNoNameMatchGoesToListSetup() async {
    // Stored list ID exists but the calendar is gone and no name match → list picker.
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-real", title: "Work")],
      reminders: ["cal-real": []]
    )
    let store = makeStore(listId: "cal-stale")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .listSetup)
  }

  // MARK: - Permission branches

  func testDeniedGoesToOnboarding() async {
    let mock = MockRemindersService(authorization: .denied)
    let store = makeStore()
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .onboarding)
  }

  func testWriteOnlyGoesToOnboarding() async {
    let mock = MockRemindersService(authorization: .writeOnly)
    let store = makeStore()
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .onboarding)
  }

  func testUndeterminedGoesToOnboarding() async {
    let mock = MockRemindersService(authorization: .undetermined)
    let store = makeStore()
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .onboarding)
  }

  // MARK: - Empty pool

  func testFullAccessEmptyPoolGoesToEmptyList() async {
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": []]
    )
    let store = makeStore(listId: "cal-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .emptyList)
    XCTAssertNil(vm.currentTask)
  }

  // MARK: - Error path

  func testFetchThrowingDuringBootstrapGoesToListSetup() async {
    // Pass a non-empty reminders dict that omits "cal-1" so the mock doesn't
    // auto-populate an empty array for it. fetchIncompleteTopLevel then throws
    // calendarNotFound, which should route to .listSetup (no userMessage — the
    // redirect is the recovery, so the alert is suppressed).
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["unrelated-cal": []]
    )
    let store = makeStore(listId: "cal-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .listSetup)
    XCTAssertNil(vm.userMessage)
  }

  // MARK: - refreshAfterSettings

  func testRefreshAfterSettingsWhileDeniedStaysOnboarding() async {
    let mock = MockRemindersService(authorization: .denied)
    let store = makeStore()
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .onboarding)
    await vm.refreshAfterSettings()
    XCTAssertEqual(vm.phase, .onboarding)
  }

  func testRefreshAfterSettingsRecoversTofocused() async {
    let task = ReminderTask(id: "r-1", title: "Do thing", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .denied,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(listId: "cal-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .onboarding)
    mock.setAuthorization(.fullAccess)
    await vm.refreshAfterSettings()
    XCTAssertEqual(vm.phase, .focused)
  }

  // MARK: - Per-list reminder memory

  func testBootstrapRestoresRememberedTaskFromMap() async {
    let r1 = ReminderTask(id: "r-1", title: "A", isCompleted: false)
    let r2 = ReminderTask(id: "r-2", title: "B", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [r1, r2]]
    )
    // Seed the map so bootstrap should restore r-2.
    let store = makeStore(listId: "cal-1", reminderId: "r-2")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.currentTask?.id, "r-2")
  }

  func testBootstrapFallsBackToRandomWhenRememberedTaskNotInPool() async {
    let r1 = ReminderTask(id: "r-1", title: "A", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [r1]]
    )
    // Seed the map with a stale reminder ID that is no longer in the pool.
    let store = makeStore(listId: "cal-1", reminderId: "r-gone")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.phase, .focused)
    // Falls back to the only available task.
    XCTAssertEqual(vm.currentTask?.id, "r-1")
  }
}
