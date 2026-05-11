import SwiftUI

struct SidebarView: View {
    @Binding var selection: NavSelection?
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var settings: AppSettings

    @State private var daysExpanded = true
    @State private var weeksExpanded = true
    @State private var monthsExpanded = true
    @State private var yearsExpanded = true

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
                    // All
                    SidebarRow(
                        label: "All Tasks",
                        icon: "square.grid.2x2",
                        isSelected: selection == .all
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) { selection = .all }
                    }
                    .padding(.top, 8)

                    // Days — only rendered when tasks have day deadlines
                    let days = store.distinctDays()
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

                    // Weeks — only rendered when tasks have week deadlines
                    let weeks = store.distinctWeeks(weekStartsOn: settings.weekStartsOn)
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

                    // Months — only rendered when tasks have month deadlines
                    let months = store.distinctMonths()
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

                    // Years — only rendered when tasks have year deadlines
                    let years = store.distinctYears()
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

            // Settings at bottom
            SidebarRow(
                label: "Settings",
                icon: "gear",
                isSelected: selection == .settings
            ) {
                withAnimation(.easeInOut(duration: 0.18)) { selection = .settings }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .onChange(of: settings.weekStartsOn) { _, newValue in
            // Re-normalize the selected week-start date so the row stays highlighted.
            if case .week(let date) = selection {
                selection = .week(date.startOfWeek(weekStartsOn: newValue))
            }
        }
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

// MARK: - Row

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
