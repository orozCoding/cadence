import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @State private var hidePastDone = false

    var body: some View {
        VStack(spacing: 0) {
            // App title
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
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
                    let today = settings.currentDate
                    let currentWeekStart = settings.currentDate.startOfWeek(weekStartsOn: settings.weekStartsOn)
                    let currentMonthStart = settings.currentDate.startOfMonth()
                    let currentYear = Calendar.current.component(.year, from: settings.currentDate)

                    // All Tasks + hide-past-done toggle
                    SidebarRow(label: "All Tasks", icon: "square.grid.2x2", isSelected: selection == .all) {
                        withAnimation(.easeInOut(duration: 0.18)) { selection = .all }
                    }
                    .overlay(alignment: .trailing) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { hidePastDone.toggle() }
                        } label: {
                            Image(systemName: hidePastDone ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(hidePastDone ? AppTheme.accent : AppTheme.textTertiary)
                                .padding(.trailing, 10)
                        }
                        .buttonStyle(.plain)
                        .help("Hide past periods with all tasks completed")
                        .pointerCursor()
                    }
                    .padding(.top, 8)

                    // Days
                    let allDays = store.distinctDays(folderId: fid)
                    let days: [Date] = hidePastDone
                        ? allDays.filter { day in
                            guard day < today else { return true }
                            return store.tasks(forDay: day, folderId: fid).contains { !$0.isDone }
                          }
                        : allDays
                    if !days.isEmpty {
                        SidebarSection(label: "Days", isExpanded: $daysExpanded) {
                            ForEach(days, id: \.self) { day in
                                let dayTasks = store.tasks(forDay: day, folderId: fid)
                                let incompleteCount = dayTasks.filter { !$0.isDone }.count
                                SidebarPeriodRow(
                                    label: day.dayLabel(today: settings.currentDate),
                                    icon: "sun.max",
                                    isSelected: selection == .day(day),
                                    isPast: day < today,
                                    incompleteCount: incompleteCount,
                                    allDone: incompleteCount == 0,
                                    action: { withAnimation(.easeInOut(duration: 0.18)) { selection = .day(day) } },
                                    onDrop: { providers in loadAndMove(providers, to: .day(day)) }
                                )
                            }
                        }
                    }

                    // Weeks
                    let allWeeks = store.distinctWeeks(weekStartsOn: settings.weekStartsOn, folderId: fid)
                    let weeks: [Date] = hidePastDone
                        ? allWeeks.filter { weekStart in
                            guard weekStart < currentWeekStart else { return true }
                            return store.tasks(forWeek: weekStart, weekStartsOn: settings.weekStartsOn, folderId: fid).contains { !$0.isDone }
                          }
                        : allWeeks
                    if !weeks.isEmpty {
                        SidebarSection(label: "Weeks", isExpanded: $weeksExpanded) {
                            ForEach(weeks, id: \.self) { weekStart in
                                let weekTasks = store.tasks(forWeek: weekStart, weekStartsOn: settings.weekStartsOn, folderId: fid)
                                let incompleteCount = weekTasks.filter { !$0.isDone }.count
                                SidebarPeriodRow(
                                    label: weekStart.weekLabel(weekStartsOn: settings.weekStartsOn, today: settings.currentDate),
                                    icon: "calendar",
                                    isSelected: selection == .week(weekStart),
                                    isPast: weekStart < currentWeekStart,
                                    incompleteCount: incompleteCount,
                                    allDone: incompleteCount == 0,
                                    action: { withAnimation(.easeInOut(duration: 0.18)) { selection = .week(weekStart) } },
                                    onDrop: { providers in loadAndMove(providers, to: .week(weekStart)) }
                                )
                            }
                        }
                    }

                    // Months
                    let allMonths = store.distinctMonths(folderId: fid)
                    let months: [Date] = hidePastDone
                        ? allMonths.filter { monthStart in
                            guard monthStart < currentMonthStart else { return true }
                            return store.tasks(forMonth: monthStart, folderId: fid).contains { !$0.isDone }
                          }
                        : allMonths
                    if !months.isEmpty {
                        SidebarSection(label: "Months", isExpanded: $monthsExpanded) {
                            ForEach(months, id: \.self) { monthStart in
                                let monthTasks = store.tasks(forMonth: monthStart, folderId: fid)
                                let incompleteCount = monthTasks.filter { !$0.isDone }.count
                                SidebarPeriodRow(
                                    label: monthStart.monthLabel(today: settings.currentDate),
                                    icon: "calendar.badge.clock",
                                    isSelected: selection == .month(monthStart),
                                    isPast: monthStart < currentMonthStart,
                                    incompleteCount: incompleteCount,
                                    allDone: incompleteCount == 0,
                                    action: { withAnimation(.easeInOut(duration: 0.18)) { selection = .month(monthStart) } },
                                    onDrop: { providers in loadAndMove(providers, to: .month(monthStart)) }
                                )
                            }
                        }
                    }

                    // Years
                    let allYears = store.distinctYears(folderId: fid)
                    let years: [Int] = hidePastDone
                        ? allYears.filter { year in
                            guard year < currentYear else { return true }
                            return store.tasks(forYear: year, folderId: fid).contains { !$0.isDone }
                          }
                        : allYears
                    if !years.isEmpty {
                        SidebarSection(label: "Years", isExpanded: $yearsExpanded) {
                            ForEach(years, id: \.self) { year in
                                let yearTasks = store.tasks(forYear: year, folderId: fid)
                                let incompleteCount = yearTasks.filter { !$0.isDone }.count
                                SidebarPeriodRow(
                                    label: year.yearLabel(today: settings.currentDate),
                                    icon: "archivebox",
                                    isSelected: selection == .year(year),
                                    isPast: year < currentYear,
                                    incompleteCount: incompleteCount,
                                    allDone: incompleteCount == 0,
                                    action: { withAnimation(.easeInOut(duration: 0.18)) { selection = .year(year) } },
                                    onDrop: { providers in loadAndMove(providers, to: .year(year)) }
                                )
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

            SidebarRow(label: "Focus Time", icon: "chart.bar.fill", isSelected: selection == .focusTime) {
                withAnimation(.easeInOut(duration: 0.18)) { selection = .focusTime }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            SidebarRow(label: "Settings", icon: "gear", isSelected: selection == .settings) {
                withAnimation(.easeInOut(duration: 0.18)) { selection = .settings }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .onChange(of: settings.weekStartsOn) { _, newValue in
            if case .week(let date) = selection {
                selection = .week(date.startOfWeek(weekStartsOn: newValue))
            }
        }
        // When the filter is active, clear selection if its period just got filtered out
        .onChange(of: store.tasks) { _, _ in validateSelection() }
        .onChange(of: hidePastDone)  { _, _ in validateSelection() }
    }

    private func validateSelection() {
        guard hidePastDone, let sel = selection else { return }
        let fid = folderStore.activeFolder.id
        let today = Date().startOfDay()
        let allDoneAndPast: Bool
        switch sel {
        case .day(let day):
            guard day < today else { return }
            allDoneAndPast = store.tasks(forDay: day, folderId: fid).allSatisfy(\.isDone)
        case .week(let weekStart):
            let cur = Date().startOfWeek(weekStartsOn: settings.weekStartsOn)
            guard weekStart < cur else { return }
            allDoneAndPast = store.tasks(forWeek: weekStart, weekStartsOn: settings.weekStartsOn, folderId: fid).allSatisfy(\.isDone)
        case .month(let monthStart):
            guard monthStart < Date().startOfMonth() else { return }
            allDoneAndPast = store.tasks(forMonth: monthStart, folderId: fid).allSatisfy(\.isDone)
        case .year(let year):
            guard year < Calendar.current.component(.year, from: Date()) else { return }
            allDoneAndPast = store.tasks(forYear: year, folderId: fid).allSatisfy(\.isDone)
        default:
            return
        }
        if allDoneAndPast {
            withAnimation(.easeInOut(duration: 0.18)) { selection = .all }
        }
    }

    private func loadAndMove(_ providers: [NSItemProvider], to period: TaskPeriod) {
        let weekStartsOn = settings.weekStartsOn
        providers.first?.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            guard let str = item as? String, let id = UUID(uuidString: str) else { return }
            DispatchQueue.main.async {
                store.moveToPeriod(taskId: id, period: period, weekStartsOn: weekStartsOn)
            }
        }
    }
}

// MARK: - Folder Switcher

private struct FolderSwitcher: View {
    @EnvironmentObject var folderStore: FolderStore
    @Binding var showAddFolder: Bool

    var body: some View {
        Menu {
            ForEach(folderStore.folders) { folder in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        folderStore.setActive(folder)
                    }
                } label: {
                    if folder.id == folderStore.activeFolder.id {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }
            Divider()
            Button("Add New Folder…") { showAddFolder = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.accent)
                Text(folderStore.activeFolder.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: AppTheme.cornerRadius).fill(AppTheme.hoveredItem))
        }
        .menuStyle(.borderlessButton)
        .pointerCursor()
    }
}

// MARK: - Add Folder Popover

private struct AddFolderPopover: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var folderStore: FolderStore
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Folder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)

            TextField("Folder name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(AppTheme.sidebarBackground))
                .onSubmit { createFolder() }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .pointerCursor()

                Button("Add") { createFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(name.trimmingCharacters(in: .whitespaces).isEmpty ? AppTheme.textTertiary : AppTheme.accent)
                    )
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .pointerCursor()
            }
        }
        .padding(16)
        .frame(width: 220)
    }

    private func createFolder() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        folderStore.add(name: trimmed)
        isPresented = false
    }
}

// MARK: - Section header

struct SidebarSection<Content: View>: View {
    let label: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .pointerCursor()

            if isExpanded {
                content()
            }
        }
    }
}

// MARK: - Plain row (for All Tasks, Focus Time, Settings)

struct SidebarRow: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AppTheme.accent : AppTheme.textSecondary)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? AppTheme.accentDark : AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .fill(isSelected ? AppTheme.selectedItem : (isHovered ? AppTheme.hoveredItem : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .pointerCursor()
    }
}

// MARK: - Period row (Days / Weeks / Months / Years — past/done state + drag-and-drop target)

struct SidebarPeriodRow: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let isPast: Bool
    let incompleteCount: Int
    let allDone: Bool
    let action: () -> Void
    let onDrop: ([NSItemProvider]) -> Void

    @State private var isHovered = false
    @State private var isTargeted = false

    private var isStrikethrough: Bool { isPast && allDone }

    var body: some View {
        ZStack(alignment: .center) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(iconColor)
                        .frame(width: 16)
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(labelColor)
                        .strikethrough(isStrikethrough, color: AppTheme.textTertiary)
                        .lineLimit(1)
                    Spacer()
                    if isPast && incompleteCount > 0 {
                        Text("\(incompleteCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(red: 0.85, green: 0.25, blue: 0.25)))
                    }
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                        .fill(isSelected ? AppTheme.selectedItem : (isHovered ? AppTheme.hoveredItem : Color.clear))
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .pointerCursor()

            if isTargeted {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(AppTheme.accent, lineWidth: 2)
                    .padding(1)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.plainText], isTargeted: $isTargeted) { providers in
            onDrop(providers)
            return true
        }
    }

    private var iconColor: Color {
        if isSelected { return AppTheme.accent }
        if isStrikethrough { return AppTheme.textTertiary }
        return AppTheme.textSecondary
    }

    private var labelColor: Color {
        if isSelected { return AppTheme.accentDark }
        if isStrikethrough { return AppTheme.textTertiary }
        return AppTheme.textPrimary
    }
}
