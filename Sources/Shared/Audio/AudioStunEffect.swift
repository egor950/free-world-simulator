import AVFoundation

extension AudioCoordinator {
    // MARK: - Stun Effect

    /// Applies stun effect with cinematic fade-in over 4.5 seconds.
    /// Low-pass, reverb, heartbeat, and ambient all sync to the same fade-in timeline.
    /// Player should be frozen during this fade-in.
    func applyStunEffect() async {
        guard !isMuted, !isStunned else { return }
        isStunned = true

        // Start heartbeat at zero volume — will fade in with everything else
        if let url = resourceURL(for: .heartbeatFast) {
            let player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 0
            player?.prepareToPlay()
            player?.play()
            stunHeartbeatPlayer = player
        }

        // Save ambient volume
        savedAmbientVolume = ambientPlayer?.volume ?? 0

        // Activate low-pass filter — start fully open (no filter)
        let band = stunEQ.bands[0]
        band.bypass = false
        band.frequency = 20_000  // Start with no filter — sounds are clear

        // Activate reverb — start fully dry
        stunReverb.loadFactoryPreset(.largeHall)
        stunReverb.wetDryMix = 0  // Start with no reverb

        // === CINEMATIC FADE-IN: 4.5 seconds ===
        let fadeDuration = 4.5
        let steps = 45  // 10 steps per second — smooth
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: UInt64((fadeDuration / Double(steps)) * 1_000_000_000))
            let progress = Float(step) / Float(steps)

            // Low-pass filter gradually closes: 20000 → 60 (sounds become heavily muffled)
            band.frequency = interpolate(from: 20_000, to: 60, progress: progress)

            // Reverb gradually increases: 0 → 90 (hall effect fades in)
            stunReverb.wetDryMix = 90 * progress

            // Heartbeat gradually fades in — synced with muffle
            stunHeartbeatPlayer?.volume = AudioCueID.heartbeatFast.defaultVolume * progress

            // Ambient volume gradually decreases: 100% → 5%
            if let ap = ambientPlayer, ap.isPlaying {
                ap.volume = savedAmbientVolume * (1.0 - 0.95 * progress)
            }
            setStunOutdoorDuckingMultiplier(1.0 - 0.95 * progress)
        }

        // Final state — full stun reached
        band.frequency = 60
        stunReverb.wetDryMix = 90
        stunHeartbeatPlayer?.volume = AudioCueID.heartbeatFast.defaultVolume
        if let ap = ambientPlayer {
            ap.volume = savedAmbientVolume * 0.05
        }
        setStunOutdoorDuckingMultiplier(0.05)
    }

    /// Gradually recovers from stun effect over the specified duration.
    /// ALL effects (heartbeat, low-pass, reverb, ambient) sync to the same timeline.
    /// - Parameter fastRecovery: If true, recovery takes 24 seconds instead of 75.
    func recoverFromStun(fastRecovery: Bool = false) async {
        guard isStunned else { return }

        let duration: TimeInterval = fastRecovery ? 24.0 : 75.0
        let band = stunEQ.bands[0]
        let startReverbMix = stunReverb.wetDryMix
        let startFrequency = band.frequency
        let heartbeatVolume = stunHeartbeatPlayer?.volume ?? 0
        let startOutdoorDucking = stunOutdoorDuckingMultiplier

        // Animate ALL effects over the full duration — fully synchronized
        let steps = Int(duration * 2) // 2 steps per second for smooth animation
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: UInt64((duration / Double(steps)) * 1_000_000_000))
            let progress = Float(step) / Float(steps)

            // Low-pass filter gradually opens: 100 → 20000
            band.frequency = interpolate(from: startFrequency, to: 20_000, progress: progress)

            // Reverb gradually decreases
            stunReverb.wetDryMix = interpolate(from: startReverbMix, to: 0, progress: progress)

            // Heartbeat gradually fades out — synced with low-pass and reverb
            stunHeartbeatPlayer?.volume = interpolate(from: heartbeatVolume, to: 0, progress: progress)

            // Ambient volume gradually restores: 5% → 100%
            if let ap = ambientPlayer {
                ap.volume = savedAmbientVolume * 0.05 + (savedAmbientVolume * 0.95 * progress)
            }
            setStunOutdoorDuckingMultiplier(interpolate(from: startOutdoorDucking, to: 1.0, progress: progress))
        }

        // Final cleanup — everything reaches zero at the same moment
        band.bypass = true
        band.frequency = 20_000
        stunReverb.wetDryMix = 0
        stunHeartbeatPlayer?.stop()
        stunHeartbeatPlayer = nil

        if let ap = ambientPlayer {
            ap.volume = savedAmbientVolume
        }
        setStunOutdoorDuckingMultiplier(1.0)

        isStunned = false
    }

    /// Cancels any ongoing stun recovery task.
    func cancelStunEffect() {
        stunRecoveryTask?.cancel()
        stunRecoveryTask = nil
        stunHeartbeatPlayer?.stop()
        stunHeartbeatPlayer = nil
        stunEQ.bands[0].bypass = true
        stunEQ.bands[0].frequency = 20_000
        stunReverb.wetDryMix = 0
        if let ap = ambientPlayer, isStunned {
            ap.volume = savedAmbientVolume
        }
        setStunOutdoorDuckingMultiplier(1.0)
        isStunned = false
    }

    private func setStunOutdoorDuckingMultiplier(_ multiplier: Float) {
        let safeMultiplier = max(0.0, min(1.0, multiplier))
        let previousMultiplier = max(0.001, stunOutdoorDuckingMultiplier)
        stunOutdoorDuckingMultiplier = safeMultiplier

        if let parkedPlayer = parkedOwnedCarAudioRuntime.player {
            parkedPlayer.volume *= safeMultiplier / previousMultiplier
        }
    }
}
