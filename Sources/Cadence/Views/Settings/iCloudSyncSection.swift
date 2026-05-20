import SwiftUI

/// Phase 1 Settings section for iCloud sync. Shows a toggle whose value
/// is persisted via `AppSettings.iCloudSyncEnabled`, plus an explanatory
/// paragraph. The toggle does **not** do anything yet — Phase 2+3+4 will
/// wire it to the actual transport. Exposing it now lets the user flip
/// it on once the rest lands without an additional UI change.
struct iCloudSyncSection: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iCloud Sync")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.textTertiary)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync via iCloud")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("Coming in a future update — toggle here is saved but inactive.")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $settings.iCloudSyncEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Sync via iCloud")
                    .accessibilityHint("Coming in a future update; the toggle is saved but currently has no effect.")
            }
        }
    }
}
