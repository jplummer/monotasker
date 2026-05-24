import SwiftUI

struct PermissionInstructionsView: View {
  @Environment(AppViewModel.self) private var model

  var body: some View {
    GeometryReader { proxy in
      let side = max(200, min(proxy.size.width - 48, proxy.size.height - 72))
      let upShift = proxy.size.height * PostItCardLayout.verticalUpShiftRatio
      let cardCY = proxy.size.height / 2 - upShift

      ZStack {
        LinearGradient(
          colors: [DesignColors.gradientTop, DesignColors.gradientBottom],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        // Ghost card: dashed border, slight tilt, button inside
        ZStack {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
            .foregroundStyle(.primary.opacity(0.35))

          VStack(spacing: 16) {
            Image(systemName: "lock.fill")
              .font(.system(size: 36, weight: .light))
              .foregroundStyle(.primary.opacity(0.7))
              .accessibilityHidden(true)
            Text("Reminders access needed")
              .font(.title3.weight(.semibold))
              .multilineTextAlignment(.center)
            Text("To use Monotasker, open Settings and allow Reminders access")
              .font(.body)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 24)
              .accessibilityLabel("To use Mono Tasker, open Settings and allow Reminders access")
            Button("Open Settings") {
              model.openAppSettings()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
            .accessibilityHint("Opens the Settings app to enable Reminders access")
          }
          .padding(20)
        }
        .frame(width: side, height: side)
        .rotationEffect(.degrees(-2))
        .position(x: proxy.size.width / 2, y: cardCY)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
