import SwiftUI

@main
struct MonotaskerApp: App {
  @State private var viewModel: AppViewModel
  @Environment(\.scenePhase) private var scenePhase

  init() {
    print("[TIMING] App.init start: +\(String(format: "%.3f", Date().timeIntervalSince(MonotaskerTiming.t0)))s")
    _viewModel = State(initialValue: AppViewModel(
      reminders: EventKitRemindersService(),
      selectionStore: SelectionStore(),
      selectionPolicy: UniformRandomTopLevelPolicy(),
      analytics: nil
    ))
    print("[TIMING] App.init end:   +\(String(format: "%.3f", Date().timeIntervalSince(MonotaskerTiming.t0)))s")
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(viewModel)
        .task {
          print("[TIMING] RootView .task (first frame): +\(String(format: "%.3f", Date().timeIntervalSince(MonotaskerTiming.t0)))s")
          viewModel.configureAnalytics(
            TelemetryDeckAnalyticsService(appID: AppConfig.telemetryDeckAppID)
          )
        }
    }
  }
}
