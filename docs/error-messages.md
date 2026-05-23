# Error Messages

Each situation where `userMessage` is set in `AppViewModel`, with the current behavior and a suggested replacement.

All current messages use `error.localizedDescription` — a raw system error string that is never user-friendly and often technical or empty.

---

## 1. Create list fails

**Where**: `AppViewModel.createReminderList(named:)` — user typed a list name and tapped Create; EventKit failed to save the new calendar.

**Current**: `error.localizedDescription`

**Suggested**: "I couldn't create that list. Please check that Reminders is working and try again."

---

## 2. Add task fails

**Where**: `AppViewModel.confirmAdd(title:notes:)` — user submitted a new task; EventKit failed to save the reminder.

**Current**: `error.localizedDescription`

**Suggested**: "I couldn't add that task. Please try again."

---

## 3. Save edit fails

**Where**: `AppViewModel.saveEdit(task:title:notes:)` — user saved an inline edit to title or notes; EventKit failed (non-notFound errors only — the notFound case is handled silently with a reload).

**Current**: `error.localizedDescription`

**Suggested**: "I couldn't save your changes. Please try again."

---

## 4. Complete or trash fails (single-task pool, immediate)

**Where**: `AppViewModel.executeImmediately(_:)` — pool had exactly one task; action (complete or trash) was committed immediately without an undo window; EventKit failed.

**Current**: `error.localizedDescription`

**Suggested**: "I couldn't complete that action. Please try again."

---

## 5. Complete or trash fails (multi-task pool, after undo window)

**Where**: `AppViewModel.sendToEventKit(_:)` — pool had 2+ tasks; undo window expired; EventKit failed on commit.

**Current**: `error.localizedDescription`

**Suggested**: "I couldn't save that change. Shuffle to sync your list."

---

## 6. Load pool fails after add

**Where**: `AppViewModel.loadPoolAfterAdd(createdId:priorPoolSize:)` — new task was created successfully in EventKit, but fetching the updated pool failed.

**Decision**: Swallow silently. The task was saved; any subsequent user action reloads the pool.
