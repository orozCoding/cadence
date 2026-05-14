import SwiftUI

struct DeadlineInfoSection: View {
    let task: CadenceTask
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deadlines")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)

            if let d = task.dayDeadline {
                DeadlineRow(icon: "sun.max", label: "Day", value: d.dayLabel())
            }
            if let w = task.weekStart {
                DeadlineRow(icon: "calendar", label: "Week", value: w.weekLabel(weekStartsOn: settings.weekStartsOn))
            }
            if let m = task.monthStart {
                DeadlineRow(icon: "calendar.badge.clock", label: "Month", value: m.monthLabel())
            }
            if let y = task.yearDeadline {
                DeadlineRow(icon: "archivebox", label: "Year", value: String(y))
            }
        }
    }
}
