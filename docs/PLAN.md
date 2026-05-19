# Monotasker — plan

Canonical reference for what Monotasker is, how it works, and what's left to build. Planning artifacts and historical specs live in `docs/superpowers/`.

Links: [README](../README.md)

---

## What's next

### Ship-ready polish

- [ ] **Error UX**: Replace or supplement generic `userMessage` alerts with inline / recoverable messaging where it helps.
- [ ] **Scene lifecycle**: Confirm behavior returning from background / Settings (permission changes, list edits in Reminders).
- [ ] **Device matrix**: Small phone, large phone, dark/light; toolbar, sheet detents, gradient safe areas, bottom strip + floating chrome.
- [ ] **Full VoiceOver traversal order audit** + large-text layout.
- [ ] **PermissionInstructionsView copy**: Tighten for full vs write-only access distinction; consider bullet list mirroring Settings path.

### Animations

Card interactions currently have no motion beyond keyboard-tracking and tilt. All three deserve distinct, characterful animations:

- [ ] **Re-roll / shuffle**: card flies off one edge (or back of stack) and a new one arrives — makes the randomness feel tactile.
- [ ] **Complete**: card checkmark + satisfying exit (fold, shrink-and-fly, confetti flash — TBD).
- [ ] **Discard / trash**: card crumples or slides to trash; more dismissive than complete.
- [ ] Ensure all three gate on `accessibilityReduceMotion`.

### Swipe interactions

Consider replacing or supplementing the bottom icon strip and floating chrome with swipe gestures:

- [ ] Swipe right → complete (or re-roll — decide which maps to which direction).
- [ ] Swipe left → trash.
- [ ] Swipe up/down → re-roll.
- [ ] Evaluate whether swipe + icon strip coexist or one replaces the other; swipe affordance (rubber-band preview) so the action is discoverable.

### View and behavior refinement

- [ ] **RootView**: ensure one alert at a time if `userMessage` and another modal could conflict.
- [ ] **TaskFocusView / PostItCard**: typography hierarchy; toast placement vs keyboard and safe area; optional haptic on undo commit.
- [ ] **EmptyListView**: confirm copy and visuals match TaskFocusView metaphor.
- [ ] **In-place edit**: Done on title could save + dismiss (optional shortcut).
- [ ] **Cross-cutting**: centralize spacing / corner radius tokens; haptics optional for Complete.

### Performance remaining

- [ ] Coalesce rapid `EKEventStoreChanged` notifications if reloads stack.
- [ ] Remove `[TIMING]` instrumentation (`MonotaskerTiming.swift`, prints in `MonotaskerApp.swift` and `AppViewModel.swift`) once cold-launch is confirmed stable.

### App Store and marketing assets

**Last** — after UI and branding settle.

- [ ] Screenshots (required sizes; dark + light)
- [ ] App Store copy: subtitle, description, keywords, What's New template; align with onboarding copy for consistency
- [ ] Privacy questionnaire; Privacy Policy URL if required
- [ ] Support / marketing URLs
- [ ] App Review notes for the permission flow

---

## Partial / in progress

- **Errors**: `userMessage` + generic Notice alert works but isn't inline/recoverable everywhere.
- **Accessibility**: Reduce Motion gated, VoiceOver labels on all controls. Full traversal order audit and large-text layout testing still needed.
- **Phase transitions**: crossfades implemented; continued polish in the ship-ready pass.

---

## Deferred roadmap

- **Dark mode color pass**: Light and dark mode currently use independent palettes that feel unrelated. Goals: (a) derive dark gradient colors from the light palette; (b) make dark-mode card colors noticeably more vibrant; (c) revisit app icon for dark appearance. Do a side-by-side comparison before locking.
- **Categories**: EventKit exposes `EKCalendar` (list) but not per-reminder categories. Options: (a) use reminder notes or title prefix as a lightweight tag shown on the card; (b) wait for richer EventKit APIs; (c) maintain Monotasker-side tags in `UserDefaults` keyed by reminder id. Most likely v1 = small metadata chip on card using a prefix convention or dedicated field.
- **Nested / subtask handling**: `EKReminder` has no public parent/subtask API. Run the [sections smoke test](#sections-smoke-test) first. Long-term: decide whether to suppress likely-header tasks, expose subtask count as a badge, or wait for Apple APIs.
- **Priority**: weighting or visual priority cues.
- **Sections / grouped tasks**: see [Sections smoke test](#sections-smoke-test).
- **Due dates**: "Today / overdue only" pool filter; overdue badge; caveat — completing a recurring `EKReminder` advances it rather than removing it.
- **Recurrence**: surface cadence on card; do not delete recurring reminders.
- **Widgets / Lock Screen / Live Activities**: requires App Group entitlement, WidgetKit extension target in `project.yml`, shared `UserDefaults`, `WidgetCenter.shared.reloadAllTimelines()` call from `AppViewModel`.
- **Settings screen**: beyond list switching (appearance, haptics, selection policy).

### Sections smoke test

Before implementing any sections-aware behavior, verify what EventKit returns from a sectioned list.

1. In Reminders.app, add sections to the Monotasker list and add tasks inside each.
2. Run Monotasker and re-roll several times — note whether section header names appear as tasks.
3. Document findings in `EventKitRemindersService` for future contributors.

- [ ] Run manual smoke test
- [ ] Document findings
- [ ] If section headers appear: decide on filter strategy and add a unit test

---

## Done

- **Core loop**: EventKit full-access path, pool fetch, random selection + re-roll, complete, trash, inline edit, inline add, empty list, list setup, persisted list + reminder ids.
- **Complete / trash UX**: deferred with undo toast for 2+ task pool; immediate for single-task pool. No confirmation alert.
- **Add feedback**: "Task added." toast after successful add.
- **All phases**: `AppPhase` and `RootView` switch, including `onboarding`.
- **First-run onboarding**: single-card-with-checkbox flow; permission gating; list auto-selection toast; list picker for cases B/C; empty-list inline edit; smooth fade-on-tap transition before permission dialog.
- **Permission denial UI**: `PermissionInstructionsView` — ghost card with dashed border, lock icon, "Open Settings" button.
- **Only-one-task alert**: with "Add another" / "Stay here".
- **External changes**: `EKEventStoreChanged` subscription reloads pool/focus.
- **Per-list reminder memory**: 50-entry LRU map in `SelectionStore`; one-time migration from legacy format.
- **Analytics**: TelemetryDeck (pseudonymous — SHA-256 hashed per-install UUID, no PII); all core + onboarding events wired; deferred init post-first-frame to stay off cold-launch path.
- **Accessibility — Reduce Motion**: all animations gated; card tilt off; toasts VoiceOver-accessible.
- **Tests**: 88 tests across 12 groups; all passing.
- **App icon**: light, dark, and tinted variants via Icon Composer.
- **Branding**: gradient palette and post-it personality locked.
- **App category**: `public.app-category.productivity`.
- **Inline add**: add card appears in TaskFocusView (replaces bottom sheet); EmptyListView auto-opens edit on appear.
- **List picker dropdown**: nav-bar title button opens `ListPickerDropdownView` overlay (replaces bottom sheet); scrim dismiss; keyboard-aware positioning.
- **Keyboard-stable card positioning**: card stays fixed while keyboard animates; equidistant between nav bar and keyboard top using `PostItCardLayout.cardRatio`.
- **Add-card color distinctness**: add card always uses a different palette entry than the current front card.
- **Cold-launch fix**: `observationTask` deferred to post-permission (accessing `Notification.Name.EKEventStoreChanged` before `remindd` was running blocked the main actor for 30+ seconds on fresh install). TelemetryDeck also moved off `App.init()` critical path.

---

## Reference

### Decisions locked

- **App name**: `Monotasker`. Centralized via `AppConfig.appName` / `CFBundleDisplayName`. Default Reminders list title follows the app name.
- **Deployment target**: iOS 18+. Uses `requestFullAccessToReminders`. `writeOnly` access is treated as insufficient and routed to permission instructions (full read access is required).
- **Random pool (v1)**: all incomplete reminders in the chosen list. Public EventKit does not expose parent/subtask relationships on `EKReminder`, so subtasks cannot be filtered at fetch time without private APIs. **Sections** in Reminders.app are a visual concept — all reminders in a list are fetched flat. Whether section "header" tasks appear in `EKReminder` results is unknown; see [Sections smoke test](#sections-smoke-test) before any sections-aware work.
- **Re-roll**: excludes the currently-selected task when the pool has ≥ 2 items; with only one task, re-roll surfaces the same task and shows the "only one task" alert.
- **Complete vs Trash**: Complete sets `isCompleted = true`; Trash removes via `EKEventStore.remove`. With **2+** tasks, both actions defer and show a **toast with Undo**; after the window expires the action commits. With **1** task, both apply immediately. No separate confirmation alert — undo covers mistaken taps.
- **Edit (v1)**: inline on the post-it (title and notes), not a separate sheet. No public URL to open a specific reminder in the system Reminders app.
- **Add task**: a control is always available on the main focus path (including empty list flows).
- **Scaffolding**: xcodegen keeps the Xcode project reproducible; `Monotasker.xcodeproj` is checked in for clone-and-open.
- **Branding**: App icon (Icon Composer, light/dark/tinted), gradient palette, and post-it personality are locked.
- **App category**: `public.app-category.productivity` (set in `project.yml`).

### Phase state machine

The happy path runs straight down the center: launch → permission check → list check → load pool → selection check → show task.

```mermaid
%%{init: {'flowchart': {'curve': 'basis', 'padding': 12}}}%%
flowchart TB
  Launch([Launch])
  Auth{Access OK?}
  ListCheck{List resolved?}
  LoadPool[Load pool]
  PoolCheck{Pool non-empty?}
  SelCheck{Selection valid?}
  ShowTask[Show task]

  Launch --> Auth
  Auth -->|full access| ListCheck
  ListCheck -->|yes| LoadPool
  LoadPool --> PoolCheck
  PoolCheck -->|yes| SelCheck
  SelCheck -->|yes| ShowTask

  Onboarding[Onboarding card]
  Instructions[Permission instructions]
  Auth -->|undetermined| Onboarding
  Onboarding -->|checkbox tap → granted| ListCheck
  Onboarding -->|checkbox tap → denied| Instructions
  Auth -->|denied / write-only| Instructions

  SetupList[List picker sheet]
  ListCheck -->|no| SetupList
  SetupList --> ListCheck

  EmptyState[Empty list]
  PoolCheck -->|no| EmptyState
  EmptyState -->|added task| LoadPool

  PickRandom[Pick at random]
  SelCheck -->|no| PickRandom
  PickRandom --> ShowTask

  AddSheet[Add task]
  ShowTask -->|complete / trash| LoadPool
  ShowTask -->|add| AddSheet
  AddSheet --> LoadPool

  Reroll[Reroll]
  ShowTask -->|reroll| Reroll
  Reroll --> ShowTask
  ShowTask -->|inline edit| ShowTask
  ShowTask -->|switch list| SetupList
```

Diagram notes:
- `denied/writeOnly`: both treated as insufficient for read needs.
- Reroll / random pick share `UniformRandomTopLevelPolicy`; see `RandomSelectionPolicy.swift`.
- Complete / trash returns to `LoadPool` after optional undo toast when pool had 2+ tasks.
- `listSetup` phase shows the card-stack background with an auto-presented list picker dropdown — not a dedicated screen.

#### List resolution (zoomed in)

Reached after permission granted, when the stored list vanished, or when the user taps the list picker.

```mermaid
%%{init: {'flowchart': {'curve': 'basis', 'padding': 12}}}%%
flowchart TB
  Enter([Enter setup])
  StoredId{Stored ID valid?}
  NameMatch{Named Monotasker?}
  Toast["Toast: We found your Monotasker list!"]
  Picker[List picker sheet]
  Persist[Persist list id]
  Exit([Return to main flow])

  Enter --> StoredId
  StoredId -->|yes| Persist
  StoredId -->|no| NameMatch
  NameMatch -->|yes| Toast
  Toast --> Persist
  NameMatch -->|no| Picker
  Picker --> Persist
  Persist --> Exit
```

- Lists come from all sources the device exposes (iCloud, local, Exchange, etc.).
- New list title is `AppConfig.appName`; source prefers `defaultCalendarForNewReminders()`, then CalDAV, then first available.
- Resolution order: persisted list id first, then first list whose title matches `AppConfig.appName`. Choice stored in `SelectionStore`.

### Architecture

- **UI**: SwiftUI, `@main` app, `@Observable` view model.
- **State**: `AppViewModel` owns `AppPhase` (`bootstrapping`, `onboarding`, `permissionDenied`, `listSetup`, `emptyList`, `focused`), pool, current `ReminderTask`, sheets, alerts, and undo state.
- **Reminders**: `RemindersService` protocol; `EventKitRemindersService` for device (lazy `EKEventStore` — not initialized until first use); `MockRemindersService` for tests.
- **Persistence**: `SelectionStore` (`UserDefaults`) — list id + per-list LRU map (up to 50 entries) of last focused reminder id per list. One-time migration from legacy single-key format on first launch after upgrade.
- **Analytics**: `AnalyticsService` protocol; `TelemetryDeckAnalyticsService` for production (initialized post-first-frame via `.task`); `MockAnalyticsService` for tests. Injected optionally into `AppViewModel`.
- **External changes**: `EKEventStoreChanged` triggers reload so edits from the Reminders app stay consistent. Observer starts lazily after permissions confirmed.

#### Random selection

`UniformRandomTopLevelPolicy` implements uniform random choice with optional "excluding" id for re-roll. When excluding removes all candidates (single-task pool), the policy falls back to the full pool and the UI shows the "only one task" flow.

#### Add-task surfacing rule

Behavior depends on pool size when add started:
- **0** in pool → focus the new task.
- **1** → focus the new task (including "Add another" from the only-one alert).
- **2+** → keep current task; the new reminder joins the pool silently.

Implemented via `poolSizeWhenAddOpened` in `AppViewModel`.

#### Visual design

- Gradient background + post-it card (`PostItCard`, `DesignColors` with asset + RGB fallbacks).
- Focus screen: **bottom icon strip** (re-roll, trash), **floating chrome** on/near the card (complete — upper-left checkbox; edit — bottom-right pencil; add — below lower-right corner); navigation bar holds the **list picker button** (opens a sheet).
- Post-action **toasts**: undo for complete/trash (multi-task pool), "Task added." after add, "We found your Monotasker list!" with "Change" after onboarding auto-selection. All VoiceOver-accessible.
- **Reduce Motion**: all animations gate on `accessibilityReduceMotion`; card tilt disabled when on.

#### Source layout

| Directory | Purpose |
|---|---|
| `Monotasker/App/` | `@main` entry point, `AppConfig` |
| `Monotasker/Models/` | `ReminderTask` — domain model wrapping `EKReminder` |
| `Monotasker/Services/` | `RemindersService` protocol + EventKit/mock implementations |
| `Monotasker/State/` | `AppViewModel`, `SelectionStore` |
| `Monotasker/Selection/` | `UniformRandomTopLevelPolicy` |
| `Monotasker/Views/` | All SwiftUI views |
| `Monotasker/Resources/` | `DesignColors`, asset catalogs |
| `MonotaskerTests/` | Unit tests (selection policy, selection store, view model) |

#### Renaming the app

1. Update `CFBundleDisplayName` in `Info.plist` or via `project.yml`.
2. Optionally change bundle id / target name in `project.yml`.
3. Run `xcodegen generate`.
4. Existing installs keep their chosen list id; new installs see the new default list name.

---

## Maintenance

- Keep this file in sync when core behaviors change (phases, surfacing rules, EventKit assumptions, instrumentation events).
- Regenerate the xcodegen project after `project.yml` edits; commit intentional `.pbxproj` updates.
