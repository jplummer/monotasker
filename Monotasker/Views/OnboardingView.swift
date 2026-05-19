import SwiftUI

struct OnboardingView: View {
  @Environment(AppViewModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var contentVisible = false
  @State private var frontCardAngle: Double = 0
  @FocusState private var dummyFocus: PostItEditFocus?

  // Matches TaskFocusView exactly.
  private let horizontalPadding: CGFloat = 24
  private let bottomChromeReserve: CGFloat = 72

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let side = max(200, min(size.width - horizontalPadding * 2, size.height - bottomChromeReserve))
      let upShift = size.height * PostItCardLayout.verticalUpShiftRatio
      let cx = size.width / 2
      let cy = size.height / 2 - upShift
      let half = side / 2
      let inset: CGFloat = 6
      let iconHit: CGFloat = 44
      let angle = reduceMotion ? 0.0 : frontCardAngle

      // Same rotated-point formula as TaskFocusView.postItFloatingChrome.
      let checkboxPos = PostItCardLayout.rotatedPoint(
        lx: -half + inset + iconHit / 2,
        ly: -half + 40,
        cx: cx, cy: cy, degrees: angle
      )

      ZStack {
        PostItCard(
          squareSide: side,
          isEditing: false,
          displayTitle: "Monotasker gives you one task at a time",
          displayNotes: "Check off this task and choose a Reminders list. (If you have a \"Monotasker\" list we'll use it automatically)",
          editTitle: .constant(""),
          editNotes: .constant(""),
          focus: $dummyFocus,
          stackedCardsCount: 1,
          colorIndex: 0,
          frontCardRotation: angle,
          checkboxLeadingReserve: 32
        )

        // Completion checkbox — sole CTA.
        // Geometry and styling match TaskFocusView's complete button (toolbarIconButton + checkboxPos).
        Button {
          withAnimation(reduceMotion ? .none : .easeOut(duration: 0.3)) {
            contentVisible = false
          }
          Task { await model.connectReminders() }
        } label: {
          Image(systemName: "square")
            .imageScale(.large)
            .frame(width: iconHit, height: iconHit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        .accessibilityLabel("Allow Reminders access")
        .rotationEffect(.degrees(angle))
        .position(checkboxPos)
      }
      .frame(width: size.width, height: size.height)
      .opacity(contentVisible ? 1 : 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      model.recordOnboardingImpression()
      frontCardAngle = reduceMotion ? 0 : Double.random(in: -2.5...2.5)
      let animation: Animation? = reduceMotion ? nil : .easeIn(duration: 0.25)
      withAnimation(animation) { contentVisible = true }
    }
  }


}
