# Cadence — Claude Code Guide

## Project

macOS SwiftUI app (macOS 14+, Xcode 15+). Three-column layout: sidebar navigation, task list, Pomodoro timer. Data lives in `UserDefaults` via `TaskStore`.

## How to build & run

Open `Cadence.xcodeproj` in Xcode, select the **Cadence** scheme targeting **My Mac**, press ⌘R.

## Source layout

```
Sources/Cadence/
├── CadenceApp.swift              App entry point — injects the three environment objects
├── Theme/AppTheme.swift          All colors and dimensions — edit here, not inline
├── Extensions/
│   ├── Date+Extensions.swift    Week/month/day helpers (startOfWeek, weekLabel, etc.)
│   └── View+Cursor.swift        .pointerCursor() modifier
├── Models/
│   ├── Task.swift               CadenceTask model + CadenceTask.validate(...)
│   ├── TaskStore.swift          @MainActor ObservableObject — add/update/toggle/filter tasks
│   ├── FolderStore.swift        Folder management
│   └── AppSettings.swift       weekStartsOn preference (persisted)
└── Views/
    ├── ContentView.swift         Root layout + NavSelection enum + modal overlay logic
    ├── Sidebar/
    │   ├── SidebarView.swift     Sidebar shell — uses SidebarRow, SidebarSection, FolderSwitcher
    │   ├── SidebarRow.swift      Single nav row (icon + label + selected state)
    │   ├── SidebarSection.swift  Collapsible section with chevron header
    │   ├── FolderSwitcher.swift  Folder menu at sidebar bottom
    │   └── AddFolderPopover.swift  New-folder popover form
    ├── Tasks/
    │   ├── AllTasksView.swift    "All Tasks" center view with sort picker
    │   ├── PeriodTasksView.swift Day/Week/Month/Year center view
    │   ├── TaskListView.swift    Shared scroll list — renders pending/done split for any [CadenceTask]
    │   ├── TaskRowView.swift     Individual task row (toggle + title + deadline badge)
    │   ├── TaskDetailSheet.swift Edit/view sheet — title, body, deadlines
    │   ├── NewTaskSheet.swift    Create sheet — title, body, deadline toggles, validation
    │   ├── DeadlineToggleRow.swift   Toggle row used in NewTaskSheet
    │   ├── DeadlineRow.swift         Read-only deadline display row
    │   ├── DeadlineInfoSection.swift Full deadline block used in TaskDetailSheet
    │   └── SharedTaskComponents.swift  TasksHeader, SectionHeader, EmptyStateView
    ├── Timer/
    │   ├── TimerPanelView.swift  Timer UI with preset grid and custom input
    │   ├── PresetButton.swift    Single timer preset button
    │   └── PomodoroTimer.swift   Combine-based countdown logic
    └── Settings/SettingsView.swift  Settings panel
```

## One struct per file — the most important rule

**Each Swift struct or class must live in its own file.** File name must match the type name exactly (e.g. `SidebarRow.swift` contains only `struct SidebarRow`).

This is the single biggest way to avoid merge conflicts when multiple agents or branches work in parallel. If you add a new component inside an existing file, every other branch that touches that file will conflict. If you add it in a new file, there is no conflict.

**Do:** create `Views/Sidebar/NewThing.swift` with `struct NewThing`.
**Don't:** append `struct NewThing` at the bottom of `SidebarView.swift`.

The only exception is tiny private helpers that are genuinely only usable by one type and have no standalone value (e.g. a one-line computed property extracted into a local helper). In that case, keep it in the same file, not as a top-level struct.

## Adding new UI

- **New sidebar section** → add a new query method to `TaskStore.swift`, add a new `SidebarSection` call inside `SidebarView.swift`, create any new row sub-component in its own file under `Sidebar/`.
- **New task field** → update `CadenceTask` in `Task.swift`, update `NewTaskSheet` and `TaskDetailSheet` to render it. If the field needs a new reusable input widget, create a dedicated file under `Tasks/` (e.g. `MyFieldRow.swift`).
- **New center view** → create a new file under `Views/Tasks/`, add a case to `NavSelection` in `ContentView.swift`, add a `switch` branch in `ContentView`.
- **New timer feature** → create a new file under `Views/Timer/`.

## Style conventions

- SwiftUI only — no AppKit, no UIKit.
- All colors and spacings come from `AppTheme` — never use raw hex or magic numbers.
- Use `.pointerCursor()` on every interactive element.
- `@EnvironmentObject` is the only DI mechanism — `TaskStore`, `AppSettings`, `FolderStore`.
- Animations: `easeInOut(duration: 0.18)` for navigation, `easeInOut(duration: 0.25–0.28)` for list changes.
- No comments unless the WHY is non-obvious.

## Environment objects

`TaskStore`, `AppSettings`, and `FolderStore` are injected at the root in `CadenceApp.swift`. Any view that needs them must declare `@EnvironmentObject var`. Do not pass them as init parameters.

## Merge-conflict hygiene

When your branch adds something new:
- New view → new file. Never append to an existing file.
- New model field → only `Task.swift` changes (one file, one concern).
- New store method → only `TaskStore.swift` (or `FolderStore.swift`) changes.
- New theme color → only `AppTheme.swift` changes.

If your change requires touching more than two files, check whether the component belongs in an existing file or needs its own. Prefer the latter.
