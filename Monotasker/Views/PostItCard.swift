import SwiftUI

enum PostItEditFocus: Hashable {
  case title
  case notes
}

/// Shared geometry helpers used by all views that position chrome on or around the post-it card.
enum PostItCardLayout {
  /// Nudges the card above true vertical center (fraction of the available height).
  static let verticalUpShiftRatio: CGFloat = 0.14

  /// Rotates a card-local point (lx, ly) around the card center (cx, cy) by `degrees` clockwise.
  static func rotatedPoint(lx: CGFloat, ly: CGFloat, cx: CGFloat, cy: CGFloat, degrees: Double) -> CGPoint {
    let r = CGFloat(degrees * .pi / 180)
    return CGPoint(
      x: cx + lx * cos(r) - ly * sin(r),
      y: cy + lx * sin(r) + ly * cos(r)
    )
  }

  /// Vertical shift ratio that centers the card in the space above the keyboard.
  /// When keyboard is hidden returns the natural ratio; otherwise places the card
  /// equidistant between the nav bar and the keyboard top edge.
  static func cardRatio(keyboardHeight: CGFloat, containerHeight: CGFloat) -> CGFloat {
    guard keyboardHeight > 0, containerHeight > 0 else { return verticalUpShiftRatio }
    return min(0.40, keyboardHeight / (2 * containerHeight))
  }
}

extension View {
  /// Calls `action` with the keyboard height (0 when hidden) whenever the keyboard frame changes,
  /// animated to match the keyboard's own transition.
  func onKeyboardHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
    onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
      guard let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
      let duration = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
      let h = max(0, UIScreen.main.bounds.height - frame.minY)
      withAnimation(.easeInOut(duration: duration)) { action(h) }
    }
  }
}

private struct BackgroundCard: Identifiable {
  let id: Int
  let angle: Double
  let offset: CGSize
  let color: Color
}

struct PostItCard: View {
  /// Edge length of the square post-it (points).
  let squareSide: CGFloat
  let isEditing: Bool
  let displayTitle: String
  let displayNotes: String?
  @Binding var editTitle: String
  @Binding var editNotes: String
  var focus: FocusState<PostItEditFocus?>.Binding
  /// Number of open tasks — drives how many stacked cards appear behind the front card.
  var stackedCardsCount: Int = 0
  /// Index into the shared post-it color palette. Background cards cycle forward from here.
  var colorIndex: Int = 0
  /// Rotation angle for the front card in degrees. Caller owns this so floating chrome can align.
  var frontCardRotation: Double = 1.0
  /// Extra leading padding for the title content, to make room for an overlaid checkbox icon.
  var checkboxLeadingReserve: CGFloat = 0
  /// Placeholder shown in the title text field when editing and no text has been entered.
  var titlePlaceholder: String = "Title"
  /// Fraction of the container height to shift the card above center. Pass 0 to center vertically.
  var verticalUpShiftRatio: CGFloat = PostItCardLayout.verticalUpShiftRatio

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Randomly generated per-card jitter, stable for the view's lifetime.
  @State private var cardJitter: [(angle: Double, dx: CGFloat, dy: CGFloat, colorIdx: Int)] = []

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [DesignColors.gradientTop, DesignColors.gradientBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      // GeometryReader defaults to top-leading; a bare VStack there was only as wide as the
      // square, so the post-it hugged the left. A full-size ZStack keeps the card centered.
      GeometryReader { geo in
        let upShift = geo.size.height * verticalUpShiftRatio

        ZStack {
          // Background stacked cards (furthest back → closest, rendered before main card)
          ForEach(backgroundCards) { card in
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(card.color)
              .frame(width: squareSide, height: squareSide)
              .rotationEffect(.degrees(reduceMotion ? 0 : card.angle))
              .offset(
                x: reduceMotion ? 0 : card.offset.width,
                y: -upShift + (reduceMotion ? 0 : card.offset.height)
              )
          }

          // Main post-it card
          postItBody
            .frame(width: squareSide, height: squareSide)
            .background(DesignColors.postItColor(at: colorIndex))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.26), radius: 20, y: 10)
            .rotationEffect(.degrees(reduceMotion ? 0 : frontCardRotation))
            .offset(y: -upShift)
        }
        .frame(width: geo.size.width, height: geo.size.height)
      }
    }
    .onAppear { regenerateJitter(count: stackedCardsCount) }
    .onChange(of: stackedCardsCount) { _, new in regenerateJitter(count: new) }
  }

  private var backgroundCards: [BackgroundCard] {
    cardJitter.enumerated().map { i, jitter in
      BackgroundCard(
        id: i,
        angle: jitter.angle,
        offset: CGSize(width: jitter.dx, height: jitter.dy),
        color: DesignColors.postItColor(at: jitter.colorIdx)
      )
    }
  }

  private func regenerateJitter(count: Int) {
    let backCount = min(max(count - 1, 0), 2)
    cardJitter = (0..<backCount).map { _ in
      (
        angle: Double.random(in: -2.2...2.2),
        dx: CGFloat.random(in: -8...8),
        dy: CGFloat.random(in: -5...5),
        colorIdx: Int.random(in: 0..<DesignColors.postItColorCount)
      )
    }
  }

  private var postItBody: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Group {
          if isEditing {
            TextField(titlePlaceholder, text: $editTitle, axis: .vertical)
              .font(.largeTitle.weight(.semibold))
              .foregroundStyle(.primary)
              .multilineTextAlignment(.leading)
              .textFieldStyle(.plain)
              .textInputAutocapitalization(.sentences)
              .submitLabel(.return)
              .focused(focus, equals: PostItEditFocus.title)
              .onSubmit {
                focus.wrappedValue = .notes
              }
          } else {
            Text(displayTitle)
              .font(.largeTitle.weight(.semibold))
              .foregroundStyle(.primary)
              .multilineTextAlignment(.leading)
          }
        }
        .padding(.leading, checkboxLeadingReserve)
        .frame(maxWidth: .infinity, alignment: .leading)

        Group {
          if isEditing {
            TextField("Notes", text: $editNotes, axis: .vertical)
              .font(.body)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.leading)
              .lineLimit(4...14)
              .textFieldStyle(.plain)
              .textInputAutocapitalization(.sentences)
              .submitLabel(.done)
              .focused(focus, equals: PostItEditFocus.notes)
              .onSubmit {
                focus.wrappedValue = nil
              }
          } else if let displayNotes, !displayNotes.isEmpty {
            Text(displayNotes)
              .font(.body)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.leading)
          }
        }
        .padding(.leading, checkboxLeadingReserve)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .scrollIndicators(.visible)
    .scrollDismissesKeyboard(.interactively)
  }
}
