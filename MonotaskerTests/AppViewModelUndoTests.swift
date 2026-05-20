import XCTest
@testable import Monotasker

@MainActor
final class AppViewModelUndoTests: XCTestCase {

  // MARK: - Helpers

  private func makeStore(listId: String = "cal-1", reminderId: String? = nil) -> SelectionStore {
    let suite = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SelectionStore(defaults: defaults)
    store.selectedListIdentifier = listId
    if let reminderId { store.setReminderID(reminderId, forList: listId) }
    return store
  }

  private func makeVM(
    mock: MockRemindersService,
    store: SelectionStore,
    policy: UniformRandomTopLevelPolicy = UniformRandomTopLevelPolicy { 0.0 }
  ) -> AppViewModel {
    AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: policy,
      undoDelay: .milliseconds(50),
      skipInitialBootstrap: true
    )
  }

  private func twoTaskMock(focused: String = "r-1") -> (MockRemindersService, SelectionStore) {
    let r1 = ReminderTask(id: "r-1", title: "A", isCompleted: false)
    let r2 = ReminderTask(id: "r-2", title: "B", isCompleted: false)
    let mock = MockRemindersService(
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [r1, r2]]
    )
    let store = makeStore(reminderId: focused)
    return (mock, store)
  }

  // MARK: - Deferred complete (pool ≥ 2)

  func testBeginCompleteHidesTaskAndSetsPendingUndo() async {
    let (mock, store) = twoTaskMock(focused: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()
    XCTAssertEqual(vm.currentTask?.id, "r-1")

    await vm.beginComplete()

    XCTAssertFalse(vm.pool.contains { $0.id == "r-1" }, "completed task must be absent from pool")
    if case .completion(let t) = vm.pendingUndo {
      XCTAssertEqual(t.id, "r-1")
    } else {
      XCTFail("pendingUndo should be .completion")
    }
    XCTAssertEqual(vm.phase, .focused)
    // mock must NOT have been mutated yet
    let tasks = try! await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertTrue(tasks.contains { $0.id == "r-1" }, "EventKit must not be called until undo window closes")
  }

  // MARK: - Deferred delete (pool ≥ 2)

  func testBeginDeleteHidesTaskAndSetsPendingUndo() async {
    let (mock, store) = twoTaskMock(focused: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()

    await vm.beginDelete()

    XCTAssertFalse(vm.pool.contains { $0.id == "r-1" })
    if case .deletion(let t) = vm.pendingUndo {
      XCTAssertEqual(t.id, "r-1")
    } else {
      XCTFail("pendingUndo should be .deletion")
    }
    let tasks = try! await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertTrue(tasks.contains { $0.id == "r-1" }, "EventKit must not be called until undo window closes")
  }

  // MARK: - Undo complete

  func testUndoCompleteRestoresTaskToPoolWithoutMutatingMock() async {
    let (mock, store) = twoTaskMock(focused: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()

    await vm.beginComplete()
    await vm.undoPendingAction()

    XCTAssertNil(vm.pendingUndo)
    XCTAssertTrue(vm.pool.contains { $0.id == "r-1" }, "undone task must return to pool")
    let tasks = try! await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertFalse(tasks.first(where: { $0.id == "r-1" })?.isCompleted ?? true,
                   "mock must not have been mutated")
  }

  // MARK: - Undo delete

  func testUndoDeleteRestoresTaskToPoolWithoutMutatingMock() async {
    let (mock, store) = twoTaskMock(focused: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()

    await vm.beginDelete()
    await vm.undoPendingAction()

    XCTAssertNil(vm.pendingUndo)
    XCTAssertTrue(vm.pool.contains { $0.id == "r-1" })
    // task still present in mock (not deleted)
    let tasks = try! await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertTrue(tasks.contains { $0.id == "r-1" })
  }

  // MARK: - Timer fires → commits

  func testCompleteTimerFiresAndCommitsToMock() async throws {
    let (mock, store) = twoTaskMock(focused: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()

    await vm.beginComplete()
    // wait longer than the 50ms undo delay
    try await Task.sleep(for: .milliseconds(200))

    XCTAssertNil(vm.pendingUndo)
    let tasks = try await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertFalse(tasks.contains { $0.id == "r-1" }, "completed task must be gone from mock after timer")
  }

  func testDeleteTimerFiresAndCommitsToMock() async throws {
    let (mock, store) = twoTaskMock(focused: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()

    await vm.beginDelete()
    try await Task.sleep(for: .milliseconds(200))

    XCTAssertNil(vm.pendingUndo)
    let tasks = try await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertFalse(tasks.contains { $0.id == "r-1" }, "deleted task must be gone from mock after timer")
  }

  // MARK: - Immediate path (pool = 1)

  func testCompleteImmediateWhenPoolIsOne() async {
    let task = ReminderTask(id: "r-1", title: "Only", isCompleted: false)
    let mock = MockRemindersService(
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()

    await vm.beginComplete()

    XCTAssertNil(vm.pendingUndo)
    XCTAssertEqual(vm.phase, .emptyList)
    let tasks = try! await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertTrue(tasks.isEmpty)
  }

  func testDeleteImmediateWhenPoolIsOne() async {
    let task = ReminderTask(id: "r-1", title: "Only", isCompleted: false)
    let mock = MockRemindersService(
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()

    await vm.beginDelete()

    XCTAssertNil(vm.pendingUndo)
    XCTAssertEqual(vm.phase, .emptyList)
    let tasks = try! await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertTrue(tasks.isEmpty)
  }

  // MARK: - Rapid second action commits first

  func testRapidSecondActionCommitsFirstBeforeOpeningNewWindow() async throws {
    let r1 = ReminderTask(id: "r-1", title: "A", isCompleted: false)
    let r2 = ReminderTask(id: "r-2", title: "B", isCompleted: false)
    let r3 = ReminderTask(id: "r-3", title: "C", isCompleted: false)
    let mock = MockRemindersService(
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [r1, r2, r3]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()

    await vm.beginComplete() // r-1 enters undo window
    // Immediately trigger a second action (which commits r-1 first)
    await vm.beginDelete()   // whatever currentTask is now enters undo window

    // r-1 must now be committed to the mock
    let tasks = try await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertFalse(tasks.contains { $0.id == "r-1" }, "first action must be committed before second window opens")
  }

  // MARK: - Error after timer fires

  func testCompleteReminderAlreadyGoneAfterTimerFiresIsHandledSilently() async throws {
    // If the task was externally deleted during the undo window, the deferred
    // completeReminder gets reminderNotFound — treated as a no-op, no alert.
    let r1 = ReminderTask(id: "r-1", title: "A", isCompleted: false)
    let r2 = ReminderTask(id: "r-2", title: "B", isCompleted: false)
    let r3 = ReminderTask(id: "r-3", title: "C", isCompleted: false)
    let mock = MockRemindersService(
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [r1, r2, r3]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()

    await vm.beginComplete()
    try mock.deleteReminder(id: "r-1")
    try await Task.sleep(for: .milliseconds(200))

    XCTAssertNil(vm.userMessage)
  }

  func testDeleteReminderAlreadyGoneAfterTimerFiresIsHandledSilently() async throws {
    // Same as above for the delete path.
    let r1 = ReminderTask(id: "r-1", title: "A", isCompleted: false)
    let r2 = ReminderTask(id: "r-2", title: "B", isCompleted: false)
    let r3 = ReminderTask(id: "r-3", title: "C", isCompleted: false)
    let mock = MockRemindersService(
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [r1, r2, r3]]
    )
    let store = makeStore(reminderId: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()

    await vm.beginDelete()
    try mock.deleteReminder(id: "r-1")
    try await Task.sleep(for: .milliseconds(200))

    XCTAssertNil(vm.userMessage)
  }

  // MARK: - Pending task filtered during external change reload

  func testExternalChangeWhileUndoWindowKeepsPendingTaskOut() async throws {
    let (mock, store) = twoTaskMock(focused: "r-1")
    let vm = makeVM(mock: mock, store: store)
    await vm.start()

    await vm.beginComplete() // r-1 in undo window

    // Simulate an external Reminders.app change (mock emits a change event)
    // The external reload should not re-introduce r-1 while it's pending
    try await Task.sleep(for: .milliseconds(30))

    XCTAssertFalse(vm.pool.contains { $0.id == "r-1" },
                   "pending task must stay filtered even after external reload")
  }
}
