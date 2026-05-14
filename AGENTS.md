# Cadence — Agent Collaboration Guide

This file is for AI agents working on this codebase in parallel. Read it before writing any code.

## The golden rule: one struct per file

**Never put more than one top-level `struct`, `class`, or `enum` in a file.**

When multiple agents work on different branches simultaneously, merge conflicts happen at the file level. If two agents add different things to the same file, Git will conflict. If each agent creates its own file, there is no conflict.

```
// BAD — causes conflicts
// SidebarView.swift
struct SidebarView { ... }
struct NewWidget { ... }   // ← added by agent A

// GOOD — no conflict
// SidebarView.swift        ← agent A doesn't touch this
// NewWidget.swift          ← agent A creates this new file
struct NewWidget { ... }
```

## Before writing code

1. Check what files already exist: `find Sources -name "*.swift" | sort`
2. Identify the minimal set of files your change needs to touch.
3. If you need a new component, create a new `.swift` file — don't append to an existing one.
4. File name must exactly match the type name: `struct FooBar` → `FooBar.swift`.

## Where things go

| What you're adding | Where it goes |
|---|---|
| New sidebar row variant | `Views/Sidebar/YourThing.swift` |
| New sidebar section | New `SidebarSection` call in `SidebarView.swift` + new query in `TaskStore.swift` |
| New task list feature | `Views/Tasks/YourThing.swift` |
| New center view / panel | `Views/Tasks/YourView.swift` + new `NavSelection` case in `ContentView.swift` |
| New timer feature | `Views/Timer/YourThing.swift` |
| New model field | `Models/Task.swift` only |
| New store method | `Models/TaskStore.swift` only |
| New settings option | `Models/AppSettings.swift` + `Views/Settings/SettingsView.swift` |
| New theme color / dimension | `Theme/AppTheme.swift` only |

## Shared components — use, don't duplicate

Before building something new, check whether it already exists:

| Component | File | Use it for |
|---|---|---|
| `TaskListView` | `Tasks/TaskListView.swift` | Any scrollable pending/done task list |
| `TasksHeader` | `Tasks/SharedTaskComponents.swift` | Top header with + button in center views |
| `SectionHeader` | `Tasks/SharedTaskComponents.swift` | "To Do" / "Done" dividers |
| `EmptyStateView` | `Tasks/SharedTaskComponents.swift` | Empty folder/period placeholder |
| `SidebarRow` | `Sidebar/SidebarRow.swift` | Any clickable sidebar nav item |
| `SidebarSection` | `Sidebar/SidebarSection.swift` | Collapsible sidebar group |
| `DeadlineToggleRow` | `Tasks/DeadlineToggleRow.swift` | Deadline toggle in creation/edit sheets |
| `DeadlineRow` | `Tasks/DeadlineRow.swift` | Read-only deadline display row |
| `DeadlineInfoSection` | `Tasks/DeadlineInfoSection.swift` | Full deadline block in detail sheet |
| `PresetButton` | `Timer/PresetButton.swift` | Timer preset / option button |

## Conflict-prone files — be careful

These files are touched by many features. Keep your changes minimal and surgical:

- `ContentView.swift` — only change when adding a new `NavSelection` case or a new top-level overlay.
- `TaskStore.swift` — only change when adding a new data query or mutation.
- `AppTheme.swift` — only change when adding a genuinely new color or dimension.
- `CadenceApp.swift` — rarely needs to change at all.

If two agents must both touch `ContentView.swift`, the resulting conflict is usually a one-line `switch` branch addition — easy to resolve. Make sure your additions are self-contained so the conflict is obvious.

## Style quick-reference

- Colors/spacing: always use `AppTheme.*` — never raw values.
- Cursors: add `.pointerCursor()` to every interactive element.
- DI: `@EnvironmentObject` only — `TaskStore`, `AppSettings`, `FolderStore`.
- Animations: `easeInOut(duration: 0.18)` for navigation, `0.25–0.28` for list changes.
- No comments unless the WHY is non-obvious.
- No multi-line docstrings.

## PR checklist

- [ ] Each new type is in its own file with a matching name.
- [ ] No new code appended to an existing file unless it's the primary file for that feature.
- [ ] Shared components used instead of reimplemented.
- [ ] `AppTheme` used for all colors and dimensions.
- [ ] `.pointerCursor()` on all interactive elements.
