import XCTest
@testable import Monotasker

@MainActor
final class AppViewModelEditTests: XCTestCase {

  private func makeVM(task: ReminderTask) -> (AppViewModel, MockRemindersService) {
    let suite = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SelectionStore(defaults: defaults)
    store.selectedListIdentifier = "cal-1"
    store.setReminderID(task.id, forList: "cal-1")
    let mock = MockRemindersService(
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
    return (vm, mock)
  }

  func testConfirmEditUpdatesTitleAndNotes() async throws {
    let task = ReminderTask(id: "r-1", title: "Old title", notes: "old notes", isCompleted: false)
    let (vm, mock) = makeVM(task: task)
    await vm.start()

    await vm.confirmEdit(title: "New title", notes: "new notes")

    XCTAssertEqual(vm.currentTask?.title, "New title")
    XCTAssertEqual(vm.currentTask?.notes, "new notes")
    let stored = try await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertEqual(stored.first?.title, "New title")
    XCTAssertEqual(stored.first?.notes, "new notes")
  }

  func testConfirmEditClearsNoteWhenBlank() async throws {
    let task = ReminderTask(id: "r-1", title: "Task", notes: "some notes", isCompleted: false)
    let (vm, mock) = makeVM(task: task)
    await vm.start()

    await vm.confirmEdit(title: "Task", notes: "")

    XCTAssertNil(vm.currentTask?.notes)
    let stored = try await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertNil(stored.first?.notes)
  }

  func testConfirmEditBlankTitleIsNoOp() async throws {
    let task = ReminderTask(id: "r-1", title: "Original", notes: nil, isCompleted: false)
    let (vm, mock) = makeVM(task: task)
    await vm.start()

    await vm.confirmEdit(title: "", notes: nil)

    XCTAssertEqual(vm.currentTask?.title, "Original")
    let stored = try await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertEqual(stored.first?.title, "Original")
  }

  func testConfirmEditWhitespaceTitleIsNoOp() async throws {
    let task = ReminderTask(id: "r-1", title: "Original", notes: nil, isCompleted: false)
    let (vm, mock) = makeVM(task: task)
    await vm.start()

    await vm.confirmEdit(title: "   ", notes: nil)

    XCTAssertEqual(vm.currentTask?.title, "Original")
    let stored = try await mock.fetchIncompleteTopLevel(calendarId: "cal-1")
    XCTAssertEqual(stored.first?.title, "Original")
  }

  func testConfirmEditReminderNotFoundReloadsPoolSilently() async {
    // If the task was deleted externally between edit-open and save, the save
    // silently reloads the pool rather than surfacing an alert.
    let task = ReminderTask(id: "r-1", title: "Task", notes: nil, isCompleted: false)
    let suite = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SelectionStore(defaults: defaults)
    store.selectedListIdentifier = "cal-1"
    store.setReminderID(task.id, forList: "cal-1")
    let mock = MockRemindersService(
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
    await vm.start()
    try! mock.deleteReminder(id: "r-1")

    await vm.confirmEdit(title: "New", notes: nil)

    XCTAssertNil(vm.userMessage)
    XCTAssertEqual(vm.phase, .emptyList)
  }
}
