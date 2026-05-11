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
                Image(systemName: "folder.fill")
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
        folderStore.add(name: name)
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
