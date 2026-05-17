import SwiftUI

struct OnboardingView: View {
  @Environment(AppViewModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var contentVisible = false
  @FocusState private var dummyFocus: PostItEditFocus?

  var body: some View {
    GeometryReader { proxy in
      let side = max(200, min(proxy.size.width - 48, proxy.size.height))
      let upShift = proxy.size.height * PostItCardLayout.verticalUpShiftRatio

      ZStack {
        PostItCard(
          squareSide: side,
          isEditing: false,
          displayTitle: "Select a Reminders list",
          displayNotes: "Monotask gives you one task at a time. Check off this card and choose a Reminders list of your choice.",
          editTitle: .constant(""),
          editNotes: .constant(""),
          focus: $dummyFocus,
          stackedCardsCount: 3,
          colorIndex: 0,
          frontCardRotation: reduceMotion ? 0 : 2.0,
          checkboxLeadingReserve: 32
        )

        // Completion checkbox — sole CTA. Positioned at upper-left of the front card.
        // Approximates the upper-left chrome position from TaskFocusView (unrotated; 2° visual error is negligible).
        Button {
          Task { await model.connectReminders() }
        } label: {
          Image(systemName: "square")
            .imageScale(.large)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        .accessibilityLabel("Allow Reminders access")
        .position(
          x: proxy.size.width / 2 - side / 2 + 6 + 22,
          y: proxy.size.height / 2 - upShift - side / 2 + 40
        )
      }
      .opacity(contentVisible ? 1 : 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      model.recordOnboardingImpression()
      let animation: Animation? = reduceMotion ? nil : .easeIn(duration: 0.25)
      withAnimation(animation) { contentVisible = true }
    }
  }
}
