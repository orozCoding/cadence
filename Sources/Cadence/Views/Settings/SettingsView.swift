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
            .frame(height: AppTheme.headerHeight)
            Divider().background(AppTheme.headerDivider)

            ScrollView {
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
                        // Segmented-style weekday picker with pointer cursors.
                        // accessibilityRepresentation exposes a Picker to VoiceOver so
                        // arrow-key navigation and radio-group semantics work correctly
                        // while preserving the custom visual design.
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
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.divider))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .accessibilityRepresentation {
                            Picker("Week starts on", selection: $settings.weekStartsOn) {
                                ForEach(Weekday.allCases, id: \.self) { day in
                                    Text(day.label).tag(day)
                                }
                            }
                        }
                    }
                }

                // Timer Direction section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Timer Direction")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)

                    HStack {
                        Text("Fill direction")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textPrimary)
                        Spacer()
                        HStack(spacing: 0) {
                            ForEach(TimerDirection.allCases) { direction in
                                let isSelected = settings.timerDirection == direction
                                Button(action: { settings.timerDirection = direction }) {
                                    Text(direction.label)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(isSelected ? .white : AppTheme.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? AppTheme.accent : Color.clear)
                                }
                                .buttonStyle(.plain)
                                .pointerCursor()
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 7).fill(AppTheme.divider))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .accessibilityRepresentation {
                            Picker("Fill direction", selection: $settings.timerDirection) {
                                ForEach(TimerDirection.allCases) { direction in
                                    Text(direction.label).tag(direction)
                                }
                            }
                        }
                    }
                }

                // Timer Style section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Timer Style")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textTertiary)

                    VStack(spacing: 2) {
                        ForEach(TimerStyle.allCases) { style in
                            let selected = settings.timerStyle == style
                            Button(action: { settings.timerStyle = style }) {
                                HStack(spacing: 10) {
                                    // Mini clock preview
                                    TimerClockView(
                                        style: style,
                                        progress: 0.6,
                                        isFinished: false,
                                        timeString: "12:30",
                                        isRunning: false,
                                        inverted: settings.timerDirection == .inverted,
                                        isPreview: true
                                    )
                                    .scaleEffect(0.30)
                                    .frame(width: 39, height: 39)
                                    .clipped()

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(style.label)
                                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                            .foregroundStyle(selected ? AppTheme.accent : AppTheme.textPrimary)
                                        Text(style.description)
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppTheme.textTertiary)
                                    }

                                    Spacer()

                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.accent)
                                            .font(.system(size: 15))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(selected ? AppTheme.selectedItem : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pointerCursor()
                            .accessibilityLabel(style.label)
                            .accessibilityHint(style.description)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(AppTheme.divider, lineWidth: 1)
                    )
                    .accessibilityRepresentation {
                        Picker("Timer style", selection: $settings.timerStyle) {
                            ForEach(TimerStyle.allCases) { style in
                                // Include description so VoiceOver reads "Glassy, Liquid glass fill"
                                Text("\(style.label), \(style.description)").tag(style)
                            }
                        }
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

                        Picker("Finish sound", selection: $settings.timerFinishSound) {
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
            } // ScrollView
        }
    }
}
