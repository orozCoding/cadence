import SwiftUI

enum NavSelection: Hashable {
    case all
    case day(Date)
    case week(Date)
    case month(Date)
    case year(Int)
    case settings
}

struct ContentView: View {
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var folderStore: FolderStore

    @State private var selection: NavSelection? = .all
    @State private var selectedTask: CadenceTask? = nil
    @State private var showNewTask = false
    @State private var newTaskBackdropTap = false

    var body: some View {
        HSplitView {
            SidebarView(selection: $selection)
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)
                .background(AppTheme.sidebarBackground)

            Group {
                switch selection {
                case .all, .none:
                    AllTasksView(selectedTask: $selectedTask, showNewTask: $showNewTask)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                case .day(let date):
                    PeriodTasksView(period: .day(date), selectedTask: $selectedTask, showNewTask: $showNewTask)
                        .id("day-\(date)")
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                case .week(let start):
                    PeriodTasksView(period: .week(start), selectedTask: $selectedTask, showNewTask: $showNewTask)
                        .id("week-\(start)")
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                case .month(let start):
                    PeriodTasksView(period: .month(start), selectedTask: $selectedTask, showNewTask: $showNewTask)
                        .id("month-\(start)")
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                case .year(let y):
                    PeriodTasksView(period: .year(y), selectedTask: $selectedTask, showNewTask: $showNewTask)
                        .id("year-\(y)")
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                case .settings:
                    SettingsView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: selection)
            .frame(minWidth: 320)
            .background(AppTheme.contentBackground)

            TimerPanelView()
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 340)
                .background(AppTheme.panelBackground)
        }
        .frame(minWidth: 800, minHeight: 500)
        // Reset navigation when folder changes so stale period selections don't persist
        .onChange(of: folderStore.activeFolder.id) { _, _ in
            withAnimation(.easeInOut(duration: 0.18)) { selection = .all }
        }
        // Overlay modals — background tap dismisses (same as X button)
        .overlay {
            if showNewTask {
                modalOverlay(onDismiss: { newTaskBackdropTap = true }) {
                    NewTaskSheet(
                        prefillSelection: selection,
                        onDismiss: { showNewTask = false },
                        backdropTap: $newTaskBackdropTap
                    )
                    .environmentObject(store)
                    .environmentObject(settings)
                    .environmentObject(folderStore)
                }
            }
        }
        .overlay {
            if let task = selectedTask {
                modalOverlay(onDismiss: { selectedTask = nil }) {
                    TaskDetailSheet(task: task, onDismiss: { selectedTask = nil })
                        .environmentObject(store)
                        .environmentObject(settings)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showNewTask)
        .animation(.easeInOut(duration: 0.18), value: selectedTask != nil)
    }

    @ViewBuilder
    private func modalOverlay<Content: View>(onDismiss: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            content()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.18), radius: 30, y: 10)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .accessibilityAddTraits(.isModal)
        }
        // Block all non-tap interaction with views behind the overlay
        .allowsHitTesting(true)
        .accessibilityAddTraits(.isModal)
        .transition(.opacity)
    }
}
