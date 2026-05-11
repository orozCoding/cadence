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

    @State private var selection: NavSelection? = .all
    @State private var selectedTask: CadenceTask? = nil
    @State private var showNewTask = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
                .frame(width: AppTheme.sidebarWidth)
                .background(AppTheme.sidebarBackground)

            Divider().background(AppTheme.divider)

            ZStack {
                AppTheme.contentBackground.ignoresSafeArea()

                Group {
                    switch selection {
                    case .all, .none:
                        AllTasksView(selectedTask: $selectedTask, showNewTask: $showNewTask)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    case .day(let date):
                        PeriodTasksView(
                            period: .day(date),
                            selectedTask: $selectedTask,
                            showNewTask: $showNewTask
                        )
                        .id("day-\(date)")
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    case .week(let start):
                        PeriodTasksView(
                            period: .week(start),
                            selectedTask: $selectedTask,
                            showNewTask: $showNewTask
                        )
                        .id("week-\(start)")
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    case .month(let start):
                        PeriodTasksView(
                            period: .month(start),
                            selectedTask: $selectedTask,
                            showNewTask: $showNewTask
                        )
                        .id("month-\(start)")
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    case .year(let y):
                        PeriodTasksView(
                            period: .year(y),
                            selectedTask: $selectedTask,
                            showNewTask: $showNewTask
                        )
                        .id("year-\(y)")
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    case .settings:
                        SettingsView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: selection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(AppTheme.divider)

            TimerPanelView()
                .frame(width: AppTheme.timerPanelWidth)
                .background(AppTheme.panelBackground)
        }
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: $showNewTask) {
            NewTaskSheet(prefillSelection: selection)
                .environmentObject(store)
                .environmentObject(settings)
        }
        .sheet(item: $selectedTask) { task in
            TaskDetailSheet(task: task)
                .environmentObject(store)
                .environmentObject(settings)
        }
    }
}
