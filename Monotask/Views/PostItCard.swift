import SwiftUI

enum PostItEditFocus: Hashable {
  case title
  case notes
}

/// Shared with `TaskFocusView` so floating chrome aligns with the centered post-it.
enum PostItCardLayout {
  /// Nudges the card above true vertical center (fraction of the gradient area height).
  static let verticalUpShiftRatio: CGFloat = 0.14
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

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        ZStack {
          postItBody
            .frame(width: squareSide, height: squareSide)
            .background(DesignColors.postItPaper)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            .rotationEffect(.degrees(reduceMotion ? 0 : 1))
            .offset(y: -geo.size.height * PostItCardLayout.verticalUpShiftRatio)
        }
        .frame(width: geo.size.width, height: geo.size.height)
      }
    }
  }

  private var postItBody: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Group {
          if isEditing {
            TextField("Title", text: $editTitle, axis: .vertical)
              .font(.largeTitle.weight(.semibold))
              .foregroundStyle(.primary)
              .multilineTextAlignment(.leading)
              .textFieldStyle(.plain)
              .textInputAutocapitalization(.sentences)
              .submitLabel(.next)
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
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .scrollIndicators(.visible)
    .scrollDismissesKeyboard(.interactively)
  }
}
