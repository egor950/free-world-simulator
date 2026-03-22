import AVFoundation
import Foundation

@MainActor
final class SpeechCoordinator: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private let isMuted: Bool
    private let onSpeak: ((String) -> Void)?

    init(isMuted: Bool = false, onSpeak: ((String) -> Void)? = nil) {
        self.isMuted = isMuted
        self.onSpeak = onSpeak
        super.init()
        activateAudioSessionIfNeeded()
    }

    var isSpeaking: Bool {
        !isMuted && synthesizer.isSpeaking
    }

    func speak(_ text: String) {
        onSpeak?(text)
        guard !isMuted else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.85
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
    }

    private func activateAudioSessionIfNeeded() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
        }
        #endif
    }
}
