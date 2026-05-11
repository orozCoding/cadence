import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider().background(AppTheme.divider)

            Form {
                Section {
                    Picker("Week starts on", selection: $settings.weekStartsOn) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            Text(day.label).tag(day)
                        }
                    }
                    .pickerStyle(.radioGroup)
                } header: {
                    Text("Calendar")
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 480)
            .padding(.top, 20)

            Spacer()
        }
    }
}
