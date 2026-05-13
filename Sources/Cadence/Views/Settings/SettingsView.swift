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

            VStack(alignment: .leading, spacing: 24) {
                // Calendar section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)

                    HStack {
                        Text("Week starts on")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        // Segmented-style weekday picker with pointer cursors
                        HStack(spacing: 0) {
                            ForEach(Weekday.allCases, id: \.self) { day in
                                let isSelected = settings.weekStartsOn == day
                                Button(action: { settings.weekStartsOn = day }) {
                                    Text(day.label)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? .white : AppTheme.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? AppTheme.accent : Color.clear)
                                }
                                .buttonStyle(.plain)
                                .pointerCursor()
                                .accessibilityLabel(day.label)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.divider))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }

                // Dock section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Dock")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)

                    HStack {
                        Text("Animate icon while timer runs")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        Toggle("", isOn: $settings.animateDockIcon)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }

                // Timer Sounds section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Timer Sounds")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Finish sound")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textPrimary)

                        Picker("", selection: $settings.timerFinishSound) {
                            ForEach(TimerFinishSound.allCases) { sound in
                                Text(sound.label).tag(sound)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        .onChange(of: settings.timerFinishSound) { _, newSound in
                            SoundManager.shared.playTimerFinished(sound: newSound)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 480, alignment: .leading)

            Spacer()
        }
    }
}
