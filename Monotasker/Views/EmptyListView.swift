import SwiftUI

struct EmptyListView: View {
  @Environment(AppViewModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var isEditing = false
  @State private var title = ""
  @State private var notes = ""
  @State private var isSaving = false
  @State private var frontCardAngle: Double = 1.5
  @FocusState private var editFocus: PostItEditFocus?
  @State private var keyboardHeight: CGFloat = 0

  private let horizontalPadding: CGFloat = 24
  /// Space reserved so the post-it does not cover the bottom chrome area (points).
  private let bottomChromeReserve: CGFloat = 72

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let widthBudget = size.width - horizontalPadding * 2
      let heightBudget = size.height - bottomChromeReserve
      let side = max(200, min(widthBudget, heightBudget))
      let cardRatio = PostItCardLayout.cardRatio(keyboardHeight: keyboardHeight, containerHeight: size.height)
      let upShift = size.height * cardRatio
      let cardCY = size.height / 2 - upShift

      let angle = reduceMotion ? 0.0 : frontCardAngle

      ZStack {
        // Card — switches between static placeholder and edit mode
        PostItCard(
          squareSide: side,
          isEditing: isEditing,
          displayTitle: "What do you need to do?",
          displayNotes: "Add a task to your Monotasker list",
          editTitle: $title,
          editNotes: $notes,
          focus: $editFocus,
          stackedCardsCount: 1,
          colorIndex: 0,
          frontCardRotation: angle,
          titlePlaceholder: "Add a task",
          verticalUpShiftRatio: cardRatio
        )

        // Static placeholder chrome — pencil on the card, plus below
        if !isEditing {
          // Pencil: bottom-right of the card, rotated with card tilt
          toolbarIconButton(systemName: "pencil", accessibilityLabel: "Edit") {
            beginEdit()
          }
          .rotationEffect(.degrees(angle))
          .position(PostItCardLayout.rotatedPoint(
            lx: side / 2 - 6 - 22,
            ly: side / 2 - 6 - 22,
            cx: size.width / 2,
            cy: cardCY,
            degrees: angle
          ))

          // Plus: below the lower-right corner, upright (matches TaskFocusView)
          toolbarIconButton(systemName: "plus.circle", accessibilityLabel: "Add task") {
            beginEdit()
          }
          .position(
            x: PostItCardLayout.rotatedPoint(
              lx: side / 2 - 6 - 22, ly: side / 2,
              cx: size.width / 2, cy: cardCY, degrees: angle
            ).x,
            y: PostItCardLayout.rotatedPoint(
              lx: side / 2 - 6 - 22, ly: side / 2,
              cx: size.width / 2, cy: cardCY, degrees: angle
            ).y + 22 + 20
          )
        }

      }
      .frame(width: size.width, height: size.height)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea(.keyboard)
    .onKeyboardHeightChange { keyboardHeight = $0 }
    .toolbar {
      ToolbarItem(placement: .principal) {
        if !isEditing {
          listPickerButton
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        if isEditing {
          Button("Done") {
            Task { await submitEdit() }
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
          .fontWeight(.semibold)
        }
      }
      ToolbarItem(placement: .topBarLeading) {
        if isEditing {
          Button("Cancel") { cancelEdit() }
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      frontCardAngle = reduceMotion ? 0 : Double.random(in: -2.5...2.5)
      // Defer past the first render cycle to avoid conflicting with the view's entry animation.
      DispatchQueue.main.async { beginEdit() }
    }
  }

  // MARK: - List picker button

  private var listPickerButton: some View {
    Button { model.showListPickerSheet = true } label: {
      HStack(spacing: 6) {
        Text(model.activeListSummary?.title ?? AppConfig.appName)
          .font(.headline)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .frame(width: 220)
      .transaction { $0.animation = nil }
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .accessibilityLabel("Reminders list, \(model.activeListSummary?.title ?? AppConfig.appName)")
    .accessibilityHint("Opens list picker")
  }

  // MARK: - Icon button

  private func toolbarIconButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .imageScale(.large)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    .accessibilityLabel(accessibilityLabel)
  }

  // MARK: - Edit lifecycle

  private func beginEdit() {
    isEditing = true
    editFocus = .title
  }

  private func cancelEdit() {
    isSaving = false  // defensive: reset in case submitEdit had an early exit
    title = ""
    notes = ""
    isEditing = false
    editFocus = nil
  }

  private func submitEdit() async {
    isSaving = true
    let notesValue = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    await model.addFromEmpty(title: title, notes: notesValue.isEmpty ? nil : notesValue)
    title = ""
    notes = ""
    isSaving = false
    isEditing = false
    editFocus = nil
  }
}
