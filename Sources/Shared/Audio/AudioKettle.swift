import AVFoundation

extension AudioCoordinator {
    private static let kettleLoopOverlapBeforeStartEnd: TimeInterval = 1.85
    private static let kettleLoopFadeInDuration: TimeInterval = 0.22
    private static let kettleLoopFadeOutForFinish: TimeInterval = 0.7
    private static let kettleLoopInitialVolumeMultiplier: Float = 0.38

    func startKettleHeatingAudio() {
        stopKettleHeatingAudio()
        guard !isMuted else { return }

        kettleSwitchPlayer = makePlayer(for: .kettleSwitchOn)
        kettleSwitchPlayer?.play()

        kettleHeatStartPlayer = makePlayer(for: .kettleHeatStart)
        kettleHeatStartPlayer?.play()

        let delay = max(0.05, duration(of: .kettleHeatStart) - Self.kettleLoopOverlapBeforeStartEnd)
        kettleHeatLoopStartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.startKettleHeatLoopIfNeeded()
        }
    }

    func finishKettleHeatingAudio() {
        kettleHeatLoopStartTask?.cancel()
        kettleHeatLoopStartTask = nil
        stopPlayer(&kettleHeatStartPlayer)
        stopPlayer(&kettleSwitchPlayer)

        if let loopPlayer = kettleHeatLoopPlayer {
            loopPlayer.setVolume(0, fadeDuration: Self.kettleLoopFadeOutForFinish)
            Task { @MainActor [weak self, weak loopPlayer] in
                try? await Task.sleep(nanoseconds: UInt64(Self.kettleLoopFadeOutForFinish * 1_000_000_000))
                guard let self else { return }
                loopPlayer?.stop()
                if self.kettleHeatLoopPlayer === loopPlayer {
                    self.kettleHeatLoopPlayer = nil
                }
            }
        } else {
            kettleHeatLoopPlayer = nil
        }

        guard !isMuted else { return }
        kettleHeatFinishPlayer = makePlayer(for: .kettleHeatFinish)
        kettleHeatFinishPlayer?.play()
    }

    func stopKettleHeatingAudio() {
        kettleHeatLoopStartTask?.cancel()
        kettleHeatLoopStartTask = nil
        stopPlayer(&kettleSwitchPlayer)
        stopPlayer(&kettleHeatStartPlayer)
        stopPlayer(&kettleHeatFinishPlayer)
        stopPlayer(&kettleHeatLoopPlayer)
    }

    private func startKettleHeatLoopIfNeeded() {
        guard !isMuted else { return }
        guard kettleHeatLoopPlayer == nil else { return }
        kettleHeatLoopPlayer = makePlayer(for: .kettleHeatLoop)
        kettleHeatLoopPlayer?.volume = AudioCueID.kettleHeatLoop.defaultVolume * Self.kettleLoopInitialVolumeMultiplier
        kettleHeatLoopPlayer?.play()
        kettleHeatLoopPlayer?.setVolume(AudioCueID.kettleHeatLoop.defaultVolume, fadeDuration: Self.kettleLoopFadeInDuration)
    }
}
