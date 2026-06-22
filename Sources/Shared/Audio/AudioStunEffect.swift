import AVFoundation

extension AudioCoordinator {
    // MARK: - Stun Effect

    /// Applies stun effect: heartbeat, ambient fade, low-pass filter + reverb on ALL sounds.
    /// All non-spatial effects now route through effectEngine → effectReverb → stunEQ → mainMixer,
    /// so the low-pass filter and reverb automatically affect every sound during stun.
    /// Called when the neighbor hits the player.
    func applyStunEffect() {
        guard !isMuted, !isStunned else { return }
        isStunned = true

        // Start heartbeat
        if let url = resourceURL(for: .heartbeatFast) {
            let player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            player?.volume = 0
            player?.prepareToPlay()
            player?.play()
            player?.setVolume(AudioCueID.heartbeatFast.defaultVolume, fadeDuration: 1.5)
            stunHeartbeatPlayer = player
        }

        // Save ambient volume and fade to 15%
        savedAmbientVolume = ambientPlayer?.volume ?? 0
        if let ap = ambientPlayer, ap.isPlaying {
            ap.setVolume(savedAmbientVolume * 0.15, fadeDuration: 2.0)
        }

        // Activate low-pass filter on ALL engine-routed sounds
        let band = stunEQ.bands[0]
        band.bypass = false
        band.frequency = 200

        // Activate reverb on ALL engine-routed sounds
        effectReverb.wetDryMix = 85
    }

    /// Gradually recovers from stun effect over the specified duration.
    /// - Parameter fastRecovery: If true, recovery takes 10 seconds instead of 60.
    func recoverFromStun(fastRecovery: Bool = false) async {
        guard isStunned else { return }

        let duration: TimeInterval = fastRecovery ? 10.0 : 60.0
        let band = stunEQ.bands[0]
        let startReverbMix = effectReverb.wetDryMix
        let endReverbMix: Float = 0

        // Stop heartbeat
        if let heartbeat = stunHeartbeatPlayer {
            heartbeat.setVolume(0, fadeDuration: duration * 0.3)
            let heartbeatStopDelay = UInt64(duration * 0.3 * 1_000_000_000)
            Task { @MainActor [weak heartbeat] in
                try? await Task.sleep(nanoseconds: heartbeatStopDelay)
                heartbeat?.stop()
            }
        }

        // Animate recovery over the full duration
        let steps = Int(duration * 2) // 2 steps per second for smooth animation
        for step in 1...steps {
            try? await Task.sleep(nanoseconds: UInt64((duration / Double(steps)) * 1_000_000_000))
            let progress = Float(step) / Float(steps)

            // Low-pass filter opens back up
            band.frequency = interpolate(from: band.frequency, to: 20_000, progress: progress * 0.1)

            // Reverb returns to 0
            effectReverb.wetDryMix = interpolate(from: startReverbMix, to: endReverbMix, progress: progress)

            // Restore ambient volume
            if let ap = ambientPlayer {
                let targetAmbient = savedAmbientVolume * 0.15 + (savedAmbientVolume * 0.85 * progress)
                ap.volume = targetAmbient
            }
        }

        // Clean up
        band.bypass = true
        band.frequency = 20_000
        effectReverb.wetDryMix = 0
        stunHeartbeatPlayer?.stop()
        stunHeartbeatPlayer = nil

        // Restore ambient volume fully
        if let ap = ambientPlayer {
            ap.volume = savedAmbientVolume
        }

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
        effectReverb.wetDryMix = 0
        if let ap = ambientPlayer, isStunned {
            ap.volume = savedAmbientVolume
        }
        isStunned = false
    }
}
