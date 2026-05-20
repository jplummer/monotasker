import XCTest
@testable import Monotasker

@MainActor
final class AppViewModelOnboardingTests: XCTestCase {

  private func makeStore(listId: String? = nil) -> SelectionStore {
    let suite = "test.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let store = SelectionStore(defaults: defaults)
    store.selectedListIdentifier = listId
    return store
  }

  // MARK: - connectReminders — undetermined

  func testConnectRemindersUndeterminedGrantedProceedsToFocused() async {
    let task = ReminderTask(id: "r-1", title: "Do thing", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .undetermined,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(listId: "cal-1")
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
    await vm.connectReminders()
    XCTAssertEqual(vm.phase, .focused)
    XCTAssertEqual(vm.currentTask?.id, "r-1")
  }

  func testConnectRemindersUndeterminedDeniedGoesToPermissionDenied() async {
    let mock = MockRemindersService(authorization: .undetermined)
    mock.setRequestAccessResult(false)
    let store = makeStore()
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
    await vm.connectReminders()
    XCTAssertEqual(vm.phase, .permissionDenied)
  }

  func testConnectRemindersUndeterminedErrorGoesToPermissionDenied() async {
    // Permission request throwing an error routes to .permissionDenied.
    // No userMessage — the permission-denied screen IS the recovery UI.
    let mock = MockRemindersService(authorization: .undetermined)
    mock.setRequestAccessError(MockRemindersService.MockError.generic)
    let store = makeStore()
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
    await vm.connectReminders()
    XCTAssertEqual(vm.phase, .permissionDenied)
    XCTAssertNil(vm.userMessage)
  }

  // MARK: - connectReminders — already decided

  func testConnectRemindersDeniedGoesToPermissionDenied() async {
    let mock = MockRemindersService(authorization: .denied)
    let store = makeStore()
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
    await vm.connectReminders()
    XCTAssertEqual(vm.phase, .permissionDenied)
  }

  func testConnectRemindersWriteOnlyGoesToPermissionDenied() async {
    let mock = MockRemindersService(authorization: .writeOnly)
    let store = makeStore()
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
    await vm.connectReminders()
    XCTAssertEqual(vm.phase, .permissionDenied)
  }

  func testConnectRemindersFullAccessSafetyValveProceedsToFocused() async {
    let task = ReminderTask(id: "r-1", title: "Do thing", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(listId: "cal-1")
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
    await vm.connectReminders()
    XCTAssertEqual(vm.phase, .focused)
  }

  // MARK: - Analytics

  func testConnectRemindersRecordsCtaTappedAndOutcome() async {
    let mock = MockRemindersService(authorization: .denied)
    let analytics = MockAnalyticsService()
    let store = makeStore()
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      analytics: analytics,
      skipInitialBootstrap: true
    )
    await vm.connectReminders()
    XCTAssertEqual(analytics.eventCount(named: "onboarding.cta_tapped"), 1)
    XCTAssertEqual(analytics.eventCount(named: "permission.outcome"), 1)
    XCTAssertEqual(analytics.events(named: "permission.outcome").first?["result"], "denied")
  }

  func testRecordOnboardingImpressionFiresEvent() async {
    let mock = MockRemindersService(authorization: .undetermined)
    let analytics = MockAnalyticsService()
    let store = makeStore()
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      analytics: analytics,
      skipInitialBootstrap: true
    )
    vm.recordOnboardingImpression()
    XCTAssertEqual(analytics.eventCount(named: "onboarding.impression"), 1)
  }

  // MARK: - List auto-selection during onboarding (Case A)

  func testConnectRemindersAutoSelectsMonotaskerListShowsToast() async {
    let task = ReminderTask(id: "r-1", title: "Buy milk", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .undetermined,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    // No stored list ID → resolveListAndLoad falls through to firstCalendar(named:)
    let store = makeStore(listId: nil)
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
    await vm.connectReminders()
    XCTAssertEqual(vm.phase, .focused)
    XCTAssertTrue(vm.showAutoSelectedListToast)
  }

  func testConnectRemindersNoListsOpensListPickerSheet() async {
    let mock = MockRemindersService(
      authorization: .undetermined,
      calendars: [],
      reminders: [:]
    )
    let store = makeStore(listId: nil)
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
    await vm.connectReminders()
    XCTAssertEqual(vm.phase, .listSetup)
    XCTAssertTrue(vm.showListPickerSheet)
  }

  func testBootstrapDoesNotShowAutoSelectedToast() async {
    // Return-visit bootstrap: permission already granted, "Monotasker" list found by name.
    // The toast must NOT appear on return visits.
    let task = ReminderTask(id: "r-1", title: "Buy milk", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .fullAccess,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let store = makeStore(listId: nil)
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      skipInitialBootstrap: true
    )
    await vm.start()
    XCTAssertFalse(vm.showAutoSelectedListToast)
  }

  // MARK: - Analytics for new onboarding events

  func testConnectRemindersAutoSelectFiresListAutoSelectedEvent() async {
    let task = ReminderTask(id: "r-1", title: "T", isCompleted: false)
    let mock = MockRemindersService(
      authorization: .undetermined,
      calendars: [ReminderCalendarSummary(id: "cal-1", title: "Monotasker")],
      reminders: ["cal-1": [task]]
    )
    let analytics = MockAnalyticsService()
    let store = makeStore(listId: nil)
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      analytics: analytics,
      skipInitialBootstrap: true
    )
    await vm.connectReminders()
    XCTAssertEqual(analytics.eventCount(named: "onboarding.list_auto_selected"), 1)
    XCTAssertEqual(analytics.eventCount(named: "onboarding.complete"), 1)
  }

  func testConnectRemindersNoListsFiresListPickerOpenedEvent() async {
    let mock = MockRemindersService(authorization: .undetermined, calendars: [], reminders: [:])
    let analytics = MockAnalyticsService()
    let store = makeStore(listId: nil)
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      analytics: analytics,
      skipInitialBootstrap: true
    )
    await vm.connectReminders()
    XCTAssertEqual(analytics.eventCount(named: "onboarding.list_picker_opened"), 1)
  }

  // MARK: - List picker from toast

  func testOpenListPickerFromToastDismissesToastAndOpensSheet() async {
    let mock = MockRemindersService(authorization: .undetermined)
    let analytics = MockAnalyticsService()
    let store = makeStore()
    let vm = AppViewModel(
      reminders: mock,
      selectionStore: store,
      selectionPolicy: UniformRandomTopLevelPolicy { 0.0 },
      analytics: analytics,
      skipInitialBootstrap: true
    )
    // Manually set the toast visible (simulating what showAutoSelectedListToastBriefly does)
    vm.showAutoSelectedListToast = true
    vm.openListPickerFromToast()
    XCTAssertFalse(vm.showAutoSelectedListToast)
    XCTAssertTrue(vm.showListPickerSheet)
    XCTAssertEqual(analytics.eventCount(named: "onboarding.change_tapped"), 1)
  }
}
