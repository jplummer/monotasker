# Monotask — task list

Use this file to track what to build next. Check items off as you go.

**Legend**

- **[ ]** not started · **[x]** done (update when you finish an item)

Links: [Product plan](PLAN.md) · [README](../README.md)

---

## Ship-ready — current functionality

These items tighten the existing feature set so the app feels complete and safe to use daily (before big new features).

- **App identity**: Add a real **app icon** set (and optionally a simple **launch screen** storyboard or SwiftUI splash) so the home screen and launch experience match the product.
- **Trash safety**: Add a **confirmation** (alert or undo toast) before permanently deleting a reminder, or match platform expectations clearly in copy.
- **Error UX**: Replace or supplement generic `userMessage` alerts with **inline / recoverable** messaging where it helps (e.g. save failures on add/edit).
- **Accessibility**: Audit **VoiceOver** labels and hints on all actions (focus buttons, list setup, sheets); verify **Dynamic Type** on the post-it title and empty state.
- **Scene lifecycle**: Confirm behavior when returning from **background** / **Settings** (permission changes, list edits in Reminders) and fix any stale UI edge cases.
- **Device matrix**: Run on **small phone**, **large phone**, and **dark/light** to catch layout issues (toolbar, sheet detents, gradient safe areas).
- **Store readiness** (when you approach release): privacy questionnaire, App Store screenshots, support URL — track outside this file if you prefer.

---

## View and behavior refinement

Polish each surface: layout, copy, motion, and interaction consistency.

### `RootView`

- Smoother **phase transitions** (opacity or minimal transition) between bootstrapping, permission, setup, empty, and focused.
- Ensure **one alert at a time** if both `userMessage` and another modal could conflict.

### `PermissionInstructionsView`

- Tighten **copy** for clarity (full vs write-only access).
- Optional: short **bullet list** mirroring Settings path on current iOS version.

### `ListSetupView`

- Clarify labels when **no other lists** exist vs many lists (helper text).
- Consider **default selection** when switching lists (first item vs last-used).
- Loading overlay: ensure it cannot **double-submit** create/use actions.

### `TaskFocusView` + `PostItCard`

- **Typography**: tune title vs notes hierarchy; max readable width on large phones.
- **Action row**: spacing, tap targets, and optional **ScrollView** if Dynamic Type grows buttons beyond one screen.
- **Toolbar**: “Switch list” discoverability (optional menu vs prominent placement).
- **Only-one-task alert**: review copy and button titles against real usage.

### `EmptyListView`

- Align **copy and visuals** with `TaskFocusView` (same metaphor, consistent gradient).
- Decide whether “Add with full form…” stays long-term or merges into one flow.

### `AddTaskSheet`

- **Keyboard**: default focus on title; dismiss on save; **Return** key behavior.
- **Validation**: enforce max length or trim rules if Reminders imposes limits.

### In-place edit (focus view)

- **Done** on title field could **save and dismiss** keyboard (optional shortcut).
- **Swipe / tap outside** to end editing (if desired) without new chrome.

### Cross-cutting UI

- Centralize **spacing / corner radius** tokens (small enum or struct) so post-it and sheets stay visually related.
- Review **haptics** optional for Complete (off by default or tied to Settings later).

---

## Deferred — roadmap

Ideas explicitly deferred from v1; implement when you choose to expand scope.

- **Animations / gestures**: Replace or augment the labeled icon row with gestures (swipe complete, swipe re-roll, etc.).
- **“Back of the stack” animation**: When pool ≥ 2 and add does not change focus, animate the new task visually **behind** the post-it (purely cosmetic).
- **Priority**: weighting or visual priority cues in UI and optional selection policy.
- **Due dates**: Filters (“today only”), overdue styling, or exclude not-yet-due from random pool.
- **Recurrence**: Surface recurrence info on the card without breaking EventKit’s next-instance behavior.
- **Subtasks**: If Apple exposes stable APIs, exclude or represent subtasks explicitly in the pool.
- **Settings screen**: Beyond list switching (e.g. appearance, haptics, selection policy).
- **Widgets / Lock Screen / Live Activities**: Surface current task outside the app.
- **iCloud selection sync**: Usually unnecessary because EventKit already syncs reminders; revisit only if you add non-EventKit state.

---

## Maintenance

- Keep **docs/PLAN.md** in sync when you change core behaviors (surfacing rules, phases, EventKit assumptions).
- Regenerate `**xcodegen`** project after `project.yml` edits and commit intentional `.pbxproj` updates.