import SwiftUI

struct TaskFocusView: View {
  let task: ReminderTask
  @Environment(AppViewModel.self) private var model

  @State private var isEditing = false
  @State private var draftTitle = ""
  @State private var draftNotes = ""
  @FocusState private var editFocus: PostItEditFocus?

  @State private var showNewListAlert = false
  @State private var newListName = ""
  @State private var frontCardAngle: Double = 0

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let horizontalPadding: CGFloat = 24
  /// Space reserved so the square post-it does not fully cover the bottom icon row (points).
  private let bottomChromeReserve: CGFloat = 72

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let maxSide = squareSide(maxHeight: size.height, maxWidth: size.width)
      let postIt = postItGeometry(container: size, squareSide: maxSide)

      let bottomPad = max(proxy.safeAreaInsets.bottom, 12)

      ZStack(alignment: .bottom) {
        ZStack {
          PostItCard(
            squareSide: maxSide,
            isEditing: isEditing,
            displayTitle: task.title,
            displayNotes: task.notes,
            editTitle: $draftTitle,
            editNotes: $draftNotes,
            focus: $editFocus,
            stackedCardsCount: model.pool.count,
            colorIndex: model.pool.firstIndex(where: { $0.id == task.id }) ?? 0,
            frontCardRotation: frontCardAngle,
            checkboxLeadingReserve: 32
          )

          postItFloatingChrome(postIt: postIt)
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(!isEditing)
            .opacity(isEditing ? 0 : 1)
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: isEditing)
        }

        VStack(spacing: 8) {
          if let undo = model.pendingUndo {
            Toast(message: undo.toastMessage, actionLabel: "Undo") {
              Task { await model.undoPendingAction() }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
          }
          if model.showTaskAddedToast {
            Toast(message: "Task added.")
              .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        }
        .padding(.bottom, bottomPad + 60)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.22), value: model.pendingUndo != nil)
        .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8), value: model.showTaskAddedToast)

        bottomIconStrip
          .padding(.horizontal, 28)
          .padding(.bottom, bottomPad)
          .allowsHitTesting(!isEditing)
          .accessibilityHidden(isEditing)
          .opacity(isEditing ? 0 : 1)
          .animation(reduceMotion ? .none : .easeInOut(duration: 0.15), value: isEditing)
      }
      .frame(width: size.width, height: size.height)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .toolbar {
      ToolbarItem(placement: .principal) {
        if !isEditing {
          listPickerMenu
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        if isEditing {
          Button("Done") {
            Task { await saveInlineEdit() }
          }
          .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .fontWeight(.semibold)
        }
      }
      ToolbarItem(placement: .topBarLeading) {
        if isEditing {
          Button("Cancel") {
            cancelInlineEdit()
          }
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: Binding(
      get: { model.showAddSheet },
      set: { if !$0 { model.cancelAdd() } }
    )) {
      AddTaskSheet()
    }
    .alert("New Reminders list", isPresented: $showNewListAlert) {
      TextField("List name", text: $newListName)
      Button("Create") {
        let name = newListName
        newListName = ""
        Task { await model.createReminderList(named: name) }
      }
      Button("Cancel", role: .cancel) {
        newListName = ""
      }
    } message: {
      Text("Creates a new list in Reminders and switches Monotask to it.")
    }
    .onChange(of: task.id) { _, _ in
      if isEditing { cancelInlineEdit() }
      frontCardAngle = Double.random(in: -2.5...2.5)
    }
    .onChange(of: task.title) { _, newTitle in
      if !isEditing {
        draftTitle = newTitle
      }
    }
    .onChange(of: task.notes ?? "") { _, newNotes in
      if !isEditing {
        draftNotes = newNotes
      }
    }
    .onAppear {
      draftTitle = task.title
      draftNotes = task.notes ?? ""
      frontCardAngle = Double.random(in: -2.5...2.5)
    }
    .alert(
      "That's the only task in your list right now.",
      isPresented: Binding(
        get: { model.showOnlyOneTaskAlert },
        set: { if !$0 { model.dismissOnlyOneTaskAlert() } }
      )
    ) {
      Button("Add another") {
        model.beginAddFromOnlyOneAlert()
      }
      Button("Stay here", role: .cancel) {
        model.dismissOnlyOneTaskAlert()
      }
    } message: {
      Text("Add another task to shuffle between, or stay on this one.")
    }
  }

  private var listPickerMenu: some View {
    Menu {
      let calendars = model.calendarsForSetup().sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
      let activeId = model.activeListSummary?.id
      ForEach(calendars) { cal in
        Button {
          Task { await model.applyListChoice(cal) }
        } label: {
          if cal.id == activeId {
            Label(cal.title, systemImage: "checkmark")
          } else {
            Text(cal.title)
          }
        }
      }
      Divider()
      Button("Add new list") {
        newListName = ""
        showNewListAlert = true
      }
    } label: {
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
    .accessibilityLabel("Reminders list, \(model.activeListSummary?.title ?? AppConfig.appName)")
    .accessibilityHint("Opens list of Reminders lists")
  }

  private func squareSide(maxHeight: CGFloat, maxWidth: CGFloat) -> CGFloat {
    let widthBudget = maxWidth - horizontalPadding * 2
    let heightBudget = maxHeight - bottomChromeReserve
    return max(200, min(widthBudget, heightBudget))
  }

  /// Center and half-extent of the square post-it in the shared container coordinate space.
  private func postItGeometry(container: CGSize, squareSide: CGFloat) -> (cx: CGFloat, cy: CGFloat, half: CGFloat) {
    let w = container.width
    let h = container.height
    let shift = h * PostItCardLayout.verticalUpShiftRatio
    let cx = w / 2
    let cy = h / 2 - shift
    let half = squareSide / 2
    return (cx, cy, half)
  }

  private func postItFloatingChrome(postIt: (cx: CGFloat, cy: CGFloat, half: CGFloat)) -> some View {
    let cx = postIt.cx
    let cy = postIt.cy
    let half = postIt.half
    let iconHit: CGFloat = 44
    let inset: CGFloat = 6
    let angle = reduceMotion ? 0.0 : frontCardAngle

    // Rotate the on-card icon anchor points with the card's tilt.
    let checkboxPos = rotatedPoint(
      lx: -half + inset + iconHit / 2, ly: -half + 40,
      cx: cx, cy: cy, degrees: angle
    )
    let editPos = rotatedPoint(
      lx: half - inset - iconHit / 2, ly: half - inset - iconHit / 2,
      cx: cx, cy: cy, degrees: angle
    )
    // Add lives outside the card — anchor from the rotated lower-right corner, then drop below.
    let cornerPos = rotatedPoint(
      lx: half - inset - iconHit / 2, ly: half,
      cx: cx, cy: cy, degrees: angle
    )

    return ZStack {
      // Complete: upper-left, tilts with the card.
      toolbarIconButton(systemName: "square", accessibilityLabel: "Complete") {
        Task { await model.beginComplete() }
      }
      .rotationEffect(.degrees(angle))
      .position(checkboxPos)

      // Edit: bottom-right, tilts with the card.
      toolbarIconButton(systemName: "pencil", accessibilityLabel: "Edit") {
        beginInlineEdit()
      }
      .rotationEffect(.degrees(angle))
      .position(editPos)

      // Add: below the lower-right corner, upright (not tilted with card).
      toolbarIconButton(systemName: "plus.circle", accessibilityLabel: "Add") {
        model.beginAdd()
      }
      .position(x: cornerPos.x, y: cornerPos.y + iconHit / 2 + 20)
    }
  }

  /// Rotates a card-local point (lx, ly) around the card center (cx, cy) by `degrees` clockwise.
  private func rotatedPoint(lx: CGFloat, ly: CGFloat, cx: CGFloat, cy: CGFloat, degrees: Double) -> CGPoint {
    let r = CGFloat(degrees * .pi / 180)
    return CGPoint(
      x: cx + lx * cos(r) - ly * sin(r),
      y: cy + lx * sin(r) + ly * cos(r)
    )
  }

  private var bottomIconStrip: some View {
    HStack {
      bottomBarIcon(systemName: "shuffle", accessibilityLabel: "Re-roll") {
        Task { await model.reroll() }
      }
      Spacer(minLength: 0)
      bottomBarIcon(systemName: "trash", accessibilityLabel: "Trash") {
        Task { await model.beginDelete() }
      }
    }
  }

  private func bottomBarIcon(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .imageScale(.large)
        .frame(minWidth: 48, minHeight: 48)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(.primary)
    .accessibilityLabel(accessibilityLabel)
  }

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

  private func beginInlineEdit() {
    draftTitle = task.title
    draftNotes = task.notes ?? ""
    isEditing = true
    DispatchQueue.main.async {
      editFocus = .title
    }
  }

  private func cancelInlineEdit() {
    draftTitle = task.title
    draftNotes = task.notes ?? ""
    isEditing = false
    editFocus = nil
  }

  private func saveInlineEdit() async {
    await model.confirmEdit(title: draftTitle, notes: draftNotes)
    isEditing = false
    editFocus = nil
  }
}

// MARK: - Toast

private struct Toast: View {
  let message: String
  var actionLabel: String? = nil
  var action: (() -> Void)? = nil

  var body: some View {
    HStack(spacing: 10) {
      Text(message)
      if let actionLabel {
        Text(actionLabel)
          .fontWeight(.semibold)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(.primary.opacity(0.12))
          .clipShape(Capsule())
      }
    }
    .font(.subheadline)
    .padding(.horizontal, 20)
    .padding(.vertical, 13)
    .background(.regularMaterial)
    .clipShape(Capsule())
    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    .contentShape(Capsule())
    .onTapGesture { action?() }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(action != nil ? .isButton : [])
    .accessibilityHint(action != nil ? "Tap to \(actionLabel?.lowercased() ?? "act")" : "")
  }
}
