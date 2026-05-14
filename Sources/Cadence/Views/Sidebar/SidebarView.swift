import SwiftUI

struct SidebarView: View {
    @Binding var selection: NavSelection?
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var folderStore: FolderStore

    @State private var daysExpanded = true
    @State private var weeksExpanded = true
    @State private var monthsExpanded = true
    @State private var yearsExpanded = true
    @State private var showAddFolder = false

    var body: some View {
        VStack(spacing: 0) {
            // App title
            HStack {
                Text("Cadence")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().background(AppTheme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let fid = folderStore.activeFolder.id

                    // All
                    SidebarRow(label: "All Tasks", icon: "square.grid.2x2", isSelected: selection == .all) {
                        withAnimation(.easeInOut(duration: 0.18)) { selection = .all }
                    }
                    .padding(.top, 8)

                    // Days
                    let days = store.distinctDays(folderId: fid)
                    if !days.isEmpty {
                        SidebarSection(label: "Days", isExpanded: $daysExpanded) {
                            ForEach(days, id: \.self) { day in
                                SidebarRow(
                                    label: day.isSameDay(as: Date()) ? "Today" : day.dayLabel(),
                                    icon: "sun.max",
                                    isSelected: selection == .day(day)
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) { selection = .day(day) }
                                }
                            }
                        }
                    }

                    // Weeks
                    let weeks = store.distinctWeeks(weekStartsOn: settings.weekStartsOn, folderId: fid)
                    if !weeks.isEmpty {
                        SidebarSection(label: "Weeks", isExpanded: $weeksExpanded) {
                            ForEach(weeks, id: \.self) { weekStart in
                                SidebarRow(
                                    label: weekStart.weekLabel(weekStartsOn: settings.weekStartsOn),
                                    icon: "calendar",
                                    isSelected: selection == .week(weekStart)
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) { selection = .week(weekStart) }
                                }
                            }
                        }
                    }

                    // Months
                    let months = store.distinctMonths(folderId: fid)
                    if !months.isEmpty {
                        SidebarSection(label: "Months", isExpanded: $monthsExpanded) {
                            ForEach(months, id: \.self) { monthStart in
                                SidebarRow(
                                    label: monthStart.monthLabel(),
                                    icon: "calendar.badge.clock",
                                    isSelected: selection == .month(monthStart)
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) { selection = .month(monthStart) }
                                }
                            }
                        }
                    }

                    // Years
                    let years = store.distinctYears(folderId: fid)
                    if !years.isEmpty {
                        SidebarSection(label: "Years", isExpanded: $yearsExpanded) {
                            ForEach(years, id: \.self) { year in
                                SidebarRow(
                                    label: String(year),
                                    icon: "archivebox",
                                    isSelected: selection == .year(year)
                                ) {
                                    withAnimation(.easeInOut(duration: 0.18)) { selection = .year(year) }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            Divider().background(AppTheme.divider)

            // Folder switcher
            FolderSwitcher(showAddFolder: $showAddFolder)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .popover(isPresented: $showAddFolder, arrowEdge: .top) {
                    AddFolderPopover(isPresented: $showAddFolder)
                        .environmentObject(folderStore)
                }

            Divider().background(AppTheme.divider)

            // Settings at bottom
            SidebarRow(label: "Settings", icon: "gear", isSelected: selection == .settings) {
                withAnimation(.easeInOut(duration: 0.18)) { selection = .settings }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .onChange(of: settings.weekStartsOn) { _, newValue in
            if case .week(let date) = selection {
                selection = .week(date.startOfWeek(weekStartsOn: newValue))
            }
        }
    }
}
