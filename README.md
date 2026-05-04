# Monotask

iOS 18+ app that shows one reminder at a time from a list you choose (default: a Reminders list named **Monotask**).

## Requirements

- Xcode 16+ (Swift 5.10 toolchain)
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Generate and open

```bash
cd /path/to/monotask
xcodegen generate
open Monotask.xcodeproj
```

Then select an iPhone simulator or device and run (**⌘R**).

## Signing and `xcodegen`

Putting **Development Team** only in the Xcode UI does not survive **`xcodegen generate`** (the project file is recreated). Putting it only in **YAML** is easy to get wrong and triggers **“No Account for Team”** if the ID does not match **Xcode → Settings → Accounts**.

**If Xcode says signing “requires a development team”:** the local team file is missing or still has the placeholder. Without it, **`xcodegen generate`** produces a project with **no** `DEVELOPMENT_TEAM` (the UI choice alone does not survive regeneration).

**Recommended:** keep team in **[`Monotask/Config/MonotaskSigning.local.xcconfig`](Monotask/Config/MonotaskSigning.local.xcconfig)** (gitignored). Each **`xcodegen generate`** runs a **post-generate** step: if that file does not exist, it is **copied** from [`MonotaskSigning.local.xcconfig.example`](Monotask/Config/MonotaskSigning.local.xcconfig.example).

1. Run **`xcodegen generate`** once so `MonotaskSigning.local.xcconfig` appears (or copy the example file manually).
2. Edit **`MonotaskSigning.local.xcconfig`** and replace **`XXXXXXXXXX`** with your real **10-character Team ID** — use **Build Settings → Development Team** after you have successfully picked **Personal Team** and built once (must match **Xcode → Settings → Accounts**). You can cross-check with `security find-identity -v -p codesigning` (parentheses on the `Apple Development:` line).
3. The wrapper [`Monotask/Config/MonotaskSigning.xcconfig`](Monotask/Config/MonotaskSigning.xcconfig) `#include?`s that file; it is **not** overwritten by `xcodegen`.

**If you see “No Account for Team”:** fix **Accounts** and the ID inside `MonotaskSigning.local.xcconfig` so they match; remove or fix the bad ID in that file, then build again.

[`project.local.yml`](project.local.yml) remains available for other optional overrides; prefer the xcconfig path above for **Development Team**.

## First run

Grant **full** Reminders access when prompted. The app needs read access to incomplete reminders, not write-only.

## Rename the app (and default list name)

1. Set `CFBundleDisplayName` in [`Monotask/App/Info.plist`](Monotask/App/Info.plist) (or override via `project.yml` `INFOPLIST_KEY_CFBundleDisplayName`).
2. Optionally change `PRODUCT_BUNDLE_IDENTIFIER` / target `name` in [`project.yml`](project.yml).
3. Run `xcodegen generate` again.
4. Existing installs keep the list they already picked via persisted calendar ID; only new installs use the new default list title.

## Tests

```bash
xcodegen generate
# Pick a booted or available iPhone simulator (name + OS must match an installed runtime)
xcodebuild -scheme Monotask -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.1' test
```

Verified on this machine with Xcode 16 / iOS 18.1 simulator. List devices: `xcrun simctl list devices available`.

## Product docs

- **[docs/PLAN.md](docs/PLAN.md)** — architecture, state machine, and locked decisions.
- **[docs/TASKS.md](docs/TASKS.md)** — working task list: ship-ready polish, per-view refinement, and deferred roadmap (checklist).
