import SwiftUI

struct RootView: View {
  @Environment(AppViewModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // Local copy of phase driven via withAnimation in onChange, so transitions always
  // run in a clean SwiftUI animation context — even when UIKit (e.g. the system
  // permissions dialog) is mid-dismissal and would otherwise suppress animations.
  @State private var displayedPhase: AppPhase = .bootstrapping

  var body: some View {
    ZStack {
      // Layer 1: permanent gradient, never transitions.
      gradientBackground

      // Layer 2: navigation-based content (NavigationStack). Renders below overlays
      // so its opaque system background can never cover an outgoing overlay fade.
      navigationLayer

      // Layer 3: onboarding and permission overlays. Always on top, so their
      // fade-out is never obscured by the NavigationStack background below.
      overlayLayer

      // Layer 4: list picker dropdown. Floats above everything, driven by showListPickerSheet.
      if model.showListPickerSheet {
        ListPickerDropdownView(isDismissible: model.phase != .listSetup)
      }
    }
    .onChange(of: model.phase) { _, newPhase in
      withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
        displayedPhase = newPhase
      }
    }
    .alert("Notice", isPresented: Binding(
      get: { model.userMessage != nil },
      set: { if !$0 { model.userMessage = nil } }
    )) {
      Button("OK", role: .cancel) { model.userMessage = nil }
    } message: {
      Text(model.userMessage ?? "")
    }
  }

  // MARK: - Layers

  @ViewBuilder
  private var navigationLayer: some View {
    switch displayedPhase {
    case .listSetup:
      Color.clear  // dropdown (layer 4) handles this phase

    case .emptyList:
      NavigationStack {
        EmptyListView()
      }
      .background(Color.clear)
      .transition(.opacity.animation(reduceMotion ? .none : .easeInOut(duration: 0.35)))

    case .focused:
      NavigationStack {
        if let task = model.currentTask {
          TaskFocusView(task: task)
        } else {
          Color.clear
        }
      }
      .background(Color.clear)
      .opacity(model.isListSwitching ? 0 : 1)
      .animation(reduceMotion ? .none : .easeInOut(duration: 0.3), value: model.isListSwitching)
      // Delayed insertion: overlay fades out first, gradient shows alone, then task fades in.
      .transition(.asymmetric(
        insertion: .opacity.animation(
          reduceMotion ? .none : .easeIn(duration: 0.45).delay(0.35)
        ),
        removal: .opacity.animation(reduceMotion ? .none : .easeOut(duration: 0.35))
      ))

    default:
      Color.clear
    }
  }

  @ViewBuilder
  private var overlayLayer: some View {
    switch displayedPhase {
    case .onboarding:
      OnboardingView()

    case .permissionDenied:
      PermissionInstructionsView()
        .transition(.opacity.animation(reduceMotion ? .none : .easeInOut(duration: 0.35)))

    default:
      // No overlay — use EmptyView so hit testing passes through to the layer below.
      EmptyView()
    }
  }

  // MARK: - Helpers

  private var gradientBackground: some View {
    LinearGradient(
      colors: [DesignColors.gradientTop, DesignColors.gradientBottom],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .ignoresSafeArea()
  }
}
