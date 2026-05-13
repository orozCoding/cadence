import AppKit
import AVFoundation

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private var player: AVAudioPlayer?
    private var systemSound: NSSound?

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    private init() {}

    func stopAll() {
        player?.stop()
        player = nil
        systemSound?.stop()
        systemSound = nil
    }

    func playTimerStart() {
        guard !AppSettings.shared.soundsMuted else { return }
        playBundled("timer_start")
    }

    func playTimerPause() {
        guard !AppSettings.shared.soundsMuted else { return }
        playBundled("timer_pause")
    }

    func playTimerFinished(sound: TimerFinishSound) {
        guard !AppSettings.shared.soundsMuted else { return }
        playBundled(sound.rawValue)
    }

    func playTimerSetOrReset() {
        guard !AppSettings.shared.soundsMuted else { return }
        player?.stop()
        systemSound?.stop()
        systemSound = NSSound(named: "Tink")
        systemSound?.play()
    }

    private func playBundled(_ name: String) {
        player?.stop()
        systemSound?.stop()
        guard let url = SoundManager.resourceBundle.url(forResource: name, withExtension: "mp3") else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
