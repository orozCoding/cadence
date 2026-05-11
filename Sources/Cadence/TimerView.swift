import SwiftUI

struct TimerView: View {
    @StateObject private var timer = PomodoroTimer()

    var body: some View {
        VStack(spacing: 32) {
            Text(timer.phase.label)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(timer.timeString)
                .font(.system(size: 80, weight: .thin, design: .monospaced))

            HStack(spacing: 16) {
                Button(action: timer.toggle) {
                    Label(timer.isRunning ? "Pause" : "Start", systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                        .frame(width: 100)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: timer.reset) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            PhasePicker(selected: $timer.phase)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PhasePicker: View {
    @Binding var selected: PomodoroTimer.Phase

    var body: some View {
        Picker("Phase", selection: $selected) {
            ForEach(PomodoroTimer.Phase.allCases) { phase in
                Text(phase.label).tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 360)
    }
}
