# Cadence

A focused macOS productivity app combining a hierarchical to-do list with a Pomodoro timer.

---

## How to Run

### Requirements
- macOS 14 (Sonoma) or later
- Xcode 15 or later (free from the Mac App Store)

### Steps

1. **Open the project in Xcode**
   ```
   open /path/to/cadence/Cadence.xcodeproj
   ```
   Or: open Finder → navigate to where you cloned `cadence` → double-click **`Cadence.xcodeproj`**

2. **Wait for Xcode to resolve the package** (first launch only — takes ~10 seconds)

3. **Select the run target**  
   In Xcode's toolbar, make sure the scheme is set to **Cadence** and the destination is **My Mac**

4. **Run the app**  
   Press **⌘R** (or click the ▶ play button in the toolbar)

That's it — no simulators, no provisioning needed.

---

## App Overview

### Layout

The app has three columns:

| Column | What you see |
|--------|-------------|
| **Left sidebar** | Navigation: All Tasks, Days, Weeks, Months, Years, Settings |
| **Center** | Task list for the selected period |
| **Right panel** | Pomodoro / focus timer |

### Creating a Task

1. Click the **+** button (top right of the center column)
2. Enter a title and optional description
3. Toggle on any deadlines you want to assign:
   - **Day** — a specific calendar day (cannot be in the past)
   - **Week** — a week period (must contain or follow the day deadline)
   - **Month** — a month period (must contain or follow the week)
   - **Year** — a year (must match or follow the month's year)
4. Click **Add Task**

### Viewing Tasks

- **All Tasks** — every task, sortable by created date, day, week, or month
- **Days / Weeks / Months / Years** — only periods that have at least one task appear in the sidebar
- Click a period to see its tasks split into **To Do** and **Done** sections
- Click any task row to open its detail sheet

### Completing Tasks

Click the circle on the left of any task row to toggle it done/undone. The change is reflected across all views instantly.

### Focus Timer

- Select a preset (15, 25, 30, or 45 minutes) or type a custom duration
- Hit ▶ to start, ⏸ to pause, ↺ to reset
- The ring fills as time passes; it turns accent blue when done

### Settings

Click **Settings** in the sidebar to choose whether the week starts on **Monday** (default) or **Sunday**.

---

## Installing or Updating the App

To run Cadence as a standalone app (no Xcode open required), build a Release binary and drop it in `/Applications`:

```bash
cd /Users/angelorozco/OrozCoding/repositories/cadence
xcodebuild -project Cadence.xcodeproj -scheme Cadence -configuration Release CONFIGURATION_BUILD_DIR="$(pwd)/dist" build && cp -R dist/Cadence.app /Applications/Cadence.app
```

After that, open it from Spotlight, Launchpad, or Finder like any other macOS app. Run the same command whenever you want to update after pulling new changes.

---

## Data Storage

All tasks are saved locally to `UserDefaults`. No cloud sync, no account required.

---

## Project Structure

```
Sources/Cadence/
├── CadenceApp.swift              App entry point
├── Theme/AppTheme.swift          Colors & dimensions
├── Extensions/Date+Extensions.swift  Week/month helpers
├── Models/
│   ├── Task.swift                CadenceTask model + validation
│   ├── TaskStore.swift           Observable store + filtering
│   └── AppSettings.swift        Persisted user preferences
└── Views/
    ├── ContentView.swift         3-column root layout
    ├── Sidebar/SidebarView.swift Left navigation
    ├── Tasks/
    │   ├── AllTasksView.swift    "All Tasks" center view
    │   ├── PeriodTasksView.swift Day/Week/Month/Year views
    │   ├── TaskRowView.swift     Individual task row
    │   ├── TaskDetailSheet.swift Task detail & edit sheet
    │   ├── NewTaskSheet.swift    New task creation with validation
    │   └── SharedTaskComponents.swift Header, section, empty state
    ├── Timer/
    │   ├── TimerPanelView.swift  Timer UI with presets
    │   └── PomodoroTimer.swift   Timer logic (Combine)
    └── Settings/SettingsView.swift Settings panel
```
