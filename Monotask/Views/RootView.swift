import SwiftUI

struct RootView: View {
  @Environment(AppViewModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Group {
      switch model.phase {
      case .bootstrapping:
        ProgressView("Loading…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .permissionDenied:
        PermissionInstructionsView()
      case .listSetup:
        NavigationStack {
          ListSetupView()
        }
      case .emptyList:
        NavigationStack {
          EmptyListView()
        }
      case .focused:
        NavigationStack {
          if let task = model.currentTask {
            TaskFocusView(task: task)
          } else {
            ProgressView("Loading…")
          }
        }
      }
    }
    .animation(reduceMotion ? .none : .default, value: model.phase)
    .alert("Notice", isPresented: Binding(
      get: { model.userMessage != nil },
      set: { if !$0 { model.userMessage = nil } }
    )) {
      Button("OK", role: .cancel) {
        model.userMessage = nil
      }
    } message: {
      Text(model.userMessage ?? "")
    }
  }
}
