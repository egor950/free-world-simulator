import AVFoundation
#if os(macOS)
import AppKit
#endif

extension AudioCoordinator {
    func playEffect(_ cue: AudioCueID?) {
        playEffect(cue, volumeMultiplier: 1.0)
    }

    func playEffect(_ cue: AudioCueID?, volumeMultiplier: Float) {
        guard !isMuted else { return }
        guard let cue, let url = resourceURL(for: cue) else { return }
        activeEngineEffects.removeAll { !$0.isPlaying }

        if let style = spatialStyle(for: cue) {
            playSpatialEffect(cue, url: url, style: style)
            return
        }

        guard let file = try? AVAudioFile(forReading: url) else { return }

        let player = AVAudioPlayerNode()
        player.volume = cue.defaultVolume * max(0.0, min(1.0, volumeMultiplier))

        effectEngine.attach(player)
        // Connect to effectOnlyMixer → preStunMixer → stunEQ → mainMixer
        effectEngine.connect(player, to: effectOnlyMixer, format: file.processingFormat)

        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self, let player else { return }
                self.effectEngine.detach(player)
                self.activeEngineEffects.removeAll { $0 === player }
            }
        }

        player.play()
        activeEngineEffects.append(player)
    }

    /// Plays a sound with echo/reverb effect. When hallwayReverbEnabled is true,
    /// plays the sound twice with a short delay to simulate hallway echo.
    func playEffectWithReverb(_ cue: AudioCueID?) {
        guard !isMuted else { return }
        guard let cue, let url = resourceURL(for: cue) else { return }
        activeEngineEffects.removeAll { !$0.isPlaying }

        if let style = spatialStyle(for: cue) {
            playSpatialEffect(cue, url: url, style: style)
            return
        }

        // Primary sound via effectOnlyMixer
        guard let file = try? AVAudioFile(forReading: url) else { return }

        let player = AVAudioPlayerNode()
        player.volume = cue.defaultVolume

        effectEngine.attach(player)
        effectEngine.connect(player, to: effectOnlyMixer, format: file.processingFormat)

        player.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self, let player else { return }
                self.effectEngine.detach(player)
                self.activeEngineEffects.removeAll { $0 === player }
            }
        }

        player.play()
        activeEngineEffects.append(player)

        // Echo/reverb repeat when in hallway
        if hallwayReverbEnabled {
            let echoDelay: TimeInterval = 0.12
            let echoVolume: Float = cue.defaultVolume * 0.45
            DispatchQueue.main.asyncAfter(deadline: .now() + echoDelay) { [weak self] in
                guard let self, !self.isMuted else { return }
                guard let echoUrl = self.resourceURL(for: cue),
                      let echoFile = try? AVAudioFile(forReading: echoUrl) else { return }

                let echoPlayer = AVAudioPlayerNode()
                echoPlayer.volume = echoVolume

                self.effectEngine.attach(echoPlayer)
                self.effectEngine.connect(echoPlayer, to: self.effectOnlyMixer, format: echoFile.processingFormat)

                echoPlayer.scheduleFile(echoFile, at: nil, completionCallbackType: .dataPlayedBack) { [weak self, weak echoPlayer] _ in
                    Task { @MainActor in
                        guard let self, let echoPlayer else { return }
                        self.effectEngine.detach(echoPlayer)
                        self.activeEngineEffects.removeAll { $0 === echoPlayer }
                    }
                }

                echoPlayer.play()
                self.activeEngineEffects.append(echoPlayer)
            }
        }
    }

    func playStep(surfaceOverride: StepSurface? = nil) {
        guard !isMuted else { return }
        let surface = surfaceOverride ?? currentStepSurface

        switch surface {
        case .carpet:
            let cue: AudioCueID = Bool.random() ? .stepCarpet01 : .stepCarpet02
            playEffectWithReverb(cue)
        case .asphalt:
            let cues: [AudioCueID] = [.stepAsphalt01, .stepAsphalt02, .stepAsphalt03, .stepAsphalt04, .stepAsphalt05]
            let available = cues.filter { $0 != lastAsphaltStep }
            let cue = available.randomElement() ?? .stepAsphalt01
            lastAsphaltStep = cue
            playEffectWithReverb(cue)
        }
    }

    func playBlockedMovement() {
        guard !isMuted else { return }
        playEffect(.obstacleThud)
    }

    func playNavigationMarker(pan: Float = 0) {
        guard !isMuted else { return }
        navigationMarkerPlayers.removeAll { !$0.isPlaying }

        if let url = resourceURL(for: .itemPlaceMetal01) {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = 0.42
                player.pan = max(-1, min(1, pan))
                player.prepareToPlay()
                player.play()
                navigationMarkerPlayers.append(player)
                return
            } catch {
            }
        }

        #if os(macOS)
        NSSound.beep()
        #else
        playEffect(.obstacleThud)
        #endif
    }

    private func spatialStyle(for cue: AudioCueID) -> SpatialEffectStyle? {
        let neighborDoorPosition = AVAudio3DPoint(x: -8, y: 0, z: -10)

        switch cue {
        case .doorbellMain:
            return SpatialEffectStyle(
                position: neighborDoorPosition,
                reverbBlend: 95,
                reverbPreset: .largeHall,
                wetDryMix: 76,
                volumeMultiplier: 0.92
            )
        case .doorBangingHard:
            return SpatialEffectStyle(
                position: neighborDoorPosition,
                reverbBlend: 92,
                reverbPreset: .largeHall,
                wetDryMix: 80,
                volumeMultiplier: 0.95
            )
        case .doorBreakHeavy:
            return SpatialEffectStyle(
                position: neighborDoorPosition,
                reverbBlend: 94,
                reverbPreset: .cathedral,
                wetDryMix: 90,
                volumeMultiplier: 1.08
            )
        default:
            return nil
        }
    }

    private func playSpatialEffect(_ cue: AudioCueID, url: URL, style: SpatialEffectStyle) {
        do {
            if !effectEngine.isRunning {
                try effectEngine.start()
            }

            let file = try AVAudioFile(forReading: url)
            let player = AVAudioPlayerNode()
            player.renderingAlgorithm = .HRTFHQ
            player.position = style.position
            player.reverbBlend = style.reverbBlend
            player.volume = cue.defaultVolume * style.volumeMultiplier
            effectReverb.loadFactoryPreset(style.reverbPreset)
            effectReverb.wetDryMix = style.wetDryMix

            effectEngine.attach(player)
            effectEngine.connect(player, to: environmentNode, format: file.processingFormat)

            player.scheduleFile(file, at: nil) { [weak self, weak player] in
                Task { @MainActor in
                    guard let self, let player else { return }
                    player.stop()
                    self.effectEngine.detach(player)
                    self.activeSpatialPlayers.removeAll { $0 === player }
                    if self.activeSpatialPlayers.isEmpty {
                        self.applyDefaultGlobalReverb()
                    }
                }
            }

            player.play()
            activeSpatialPlayers.append(player)
        } catch {
            do {
                let fallback = try AVAudioPlayer(contentsOf: url)
                fallback.volume = cue.defaultVolume
                fallback.prepareToPlay()
                fallback.play()
                activeEffects.append(fallback)
            } catch {
            }
        }
    }

    func fadeOutAndStop(_ player: AVAudioPlayer?, duration: TimeInterval) {
        guard let player else { return }
        player.setVolume(0, fadeDuration: duration)

        Task { @MainActor in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            player.stop()
        }
    }

    func stopPlayer(_ player: inout AVAudioPlayer?) {
        player?.stop()
        player = nil
    }
}

func interpolate(from start: Float, to end: Float, progress: Float) -> Float {
    start + ((end - start) * progress)
}

func normalized(_ value: Float, start: Float, end: Float) -> Float {
    guard end > start else { return 1.0 }
    return min(1.0, max(0.0, (value - start) / (end - start)))
}

private struct SpatialEffectStyle {
    let position: AVAudio3DPoint
    let reverbBlend: Float
    let reverbPreset: AVAudioUnitReverbPreset
    let wetDryMix: Float
    let volumeMultiplier: Float
}
