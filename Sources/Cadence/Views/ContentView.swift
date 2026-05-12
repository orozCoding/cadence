import SwiftUI

enum NavSelection: Hashable {
    case all
    case day(Date)
    case week(Date)
    case month(Date)
    case year(Int)
    case focusTime
    case settings
}

enum CenterContent: Equatable {
    case list
    case newTask
    case editTask(UUID)
}

struct ContentView: View {
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var folderStore: FolderStore

    @State private var selection: NavSelection? = .all
    @State private var centerContent: CenterContent = .list

    // Shared discard guard for folder-switch and settings navigation
    @State private var showNavigationDiscardAlert = false
    @State private var navigationOnProceed: (() -> Void)? = nil
    @State private var navigationOnCancel: (() -> Void)? = nil
    @State private var isRevertingNavigation = false

    var body: some View {
        HSplitView {
            SidebarView(selection: $selection)
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
                .background(AppTheme.sidebarBackground)

            Group {
                switch centerContent {
                case .list:
                    listView
                        .transition(.opacity)
                case .newTask:
                    TaskCreateView(
                        prefillSelection: selection,
                        onBack: { withAnimation(.easeInOut(duration: 0.18)) { centerContent = .list } }
                    )
                    .environmentObject(store)
                    .environmentObject(settings)
                    .environmentObject(folderStore)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                case .editTask(let taskID):
                    if let task = store.tasks.first(where: { $0.id == taskID }) {
                        TaskEditView(
                            task: task,
                            onBack: { withAnimation(.easeInOut(duration: 0.18)) { centerContent = .list } }
                        )
                        .environmentObject(store)
                        .environmentObject(settings)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.18), value: centerContent)
            .frame(minWidth: 320)
            .background(AppTheme.contentBackground)

            TimerPanelView()
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 340)
                .background(AppTheme.panelBackground)
        }
        .frame(minWidth: 800, minHeight: 500)
        // Settings and Focus Time are full context switches — guard against silent draft loss
        .onChange(of: selection) { oldSel, newSel in
            guard !isRevertingNavigation else { isRevertingNavigation = false; return }
            guard (newSel == .settings || newSel == .focusTime), centerContent != .list else { return }
            isRevertingNavigation = true
            selection = oldSel ?? .all  // revert selection until user confirms
            let dest = newSel ?? .all
            navigationOnProceed = { withAnimation(.easeInOut(duration: 0.18)) { selection = dest; centerContent = .list } }
            navigationOnCancel = {}
            showNavigationDiscardAlert = true
        }
        // Folder switch also requires a discard guard
        .onChange(of: folderStore.activeFolder.id) { oldID, _ in
            guard !isRevertingNavigation else { isRevertingNavigation = false; return }
            guard centerContent != .list else {
                withAnimation(.easeInOut(duration: 0.18)) { selection = .all; centerContent = .list }
                return
            }
            navigationOnProceed = { withAnimation(.easeInOut(duration: 0.18)) { selection = .all; centerContent = .list } }
            navigationOnCancel = {
                guard let folder = folderStore.folders.first(where: { $0.id == oldID }) else { return }
                isRevertingNavigation = true
                folderStore.setActive(folder)
            }
            showNavigationDiscardAlert = true
        }
        .confirmationDialog("Unsaved Changes", isPresented: $showNavigationDiscardAlert, titleVisibility: .visible) {
            Button("Discard & Continue", role: .destructive) {
                navigationOnProceed?()
                navigationOnProceed = nil; navigationOnCancel = nil
            }
            Button("Keep Editing", role: .cancel) {
                navigationOnCancel?()
                navigationOnProceed = nil; navigationOnCancel = nil
            }
        } message: {
            Text("Any unsaved changes will be lost.")
        }
    }

    @ViewBuilder
    private var listView: some View {
        switch selection {
        case .all, .none:
            AllTasksView(
                onTaskTap: { task in withAnimation(.easeInOut(duration: 0.18)) { centerContent = .editTask(task.id) } },
                onNewTask: { withAnimation(.easeInOut(duration: 0.18)) { centerContent = .newTask } }
            )
            .transition(.opacity.combined(with: .move(edge: .leading)))
        case .day(let date):
            PeriodTasksView(
                period: .day(date),
                onTaskTap: { task in withAnimation(.easeInOut(duration: 0.18)) { centerContent = .editTask(task.id) } },
                onNewTask: { withAnimation(.easeInOut(duration: 0.18)) { centerContent = .newTask } }
            )
            .id("day-\(date)")
            .transition(.opacity.combined(with: .move(edge: .leading)))
        case .week(let start):
            PeriodTasksView(
                period: .week(start),
                onTaskTap: { task in withAnimation(.easeInOut(duration: 0.18)) { centerContent = .editTask(task.id) } },
                onNewTask: { withAnimation(.easeInOut(duration: 0.18)) { centerContent = .newTask } }
            )
            .id("week-\(start)")
            .transition(.opacity.combined(with: .move(edge: .leading)))
        case .month(let start):
            PeriodTasksView(
                period: .month(start),
                onTaskTap: { task in withAnimation(.easeInOut(duration: 0.18)) { centerContent = .editTask(task.id) } },
                onNewTask: { withAnimation(.easeInOut(duration: 0.18)) { centerContent = .newTask } }
            )
            .id("month-\(start)")
            .transition(.opacity.combined(with: .move(edge: .leading)))
        case .year(let y):
            PeriodTasksView(
                period: .year(y),
                onTaskTap: { task in withAnimation(.easeInOut(duration: 0.18)) { centerContent = .editTask(task.id) } },
                onNewTask: { withAnimation(.easeInOut(duration: 0.18)) { centerContent = .newTask } }
            )
            .id("year-\(y)")
            .transition(.opacity.combined(with: .move(edge: .leading)))
        case .focusTime:
            FocusTimeView()
                .transition(.opacity)
        case .settings:
            SettingsView()
                .transition(.opacity)
        }
    }
}
