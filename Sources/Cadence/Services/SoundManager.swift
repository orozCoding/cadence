import AppKit
import AVFoundation

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private var player: AVAudioPlayer?

    private init() {}

    func playTimerStart() {
        playBundled("timer_start")
    }

    func playTimerPause() {
        playBundled("timer_pause")
    }

    func playTimerFinished(sound: TimerFinishSound) {
        playBundled(sound.rawValue)
    }

    func playTimerSetOrReset() {
        player?.stop()
        NSSound(named: "Tink")?.play()
    }

    private func playBundled(_ name: String) {
        player?.stop()
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
