import AVFoundation

extension AudioCoordinator {
    func playAmbient(_ cue: AudioCueID?) {
        guard !isMuted else { return }
        guard cue != ambientCue else { return }
        let previousPlayer = ambientPlayer
        ambientCue = cue

        guard let cue, let url = resourceURL(for: cue) else {
            fadeOutAndStop(previousPlayer, duration: 0.35)
            ambientPlayer = nil
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = cue.loops ? -1 : 0
            player.prepareToPlay()

            if cue == .heartbeatFast {
                fadeOutAndStop(previousPlayer, duration: 0.45)
                player.volume = 0
                player.play()
                player.setVolume(cue.defaultVolume, fadeDuration: 1.25)
            } else {
                previousPlayer?.stop()
                player.volume = cue.defaultVolume
                player.play()
            }

            ambientPlayer = player
        } catch {
            ambientPlayer = nil
        }
    }
}
