import AVFoundation

extension AudioCoordinator {
    func setStreetPresence(_ presence: StreetPresence, fadeDuration: TimeInterval = 1.2) {
        guard !isMuted else { return }
        if presence == streetPresence, streetBedPlayer.isPlaying {
            return
        }
        streetPresence = presence
        ensureStreetBedLoopStarted()

        let target = streetBedMix(for: presence)
        streetBedTransitionTask?.cancel()

        let band = streetBedEQ.bands[0]
        let startVolume = streetBedPlayer.volume
        let startFrequency = band.frequency
        let duration = presence == .off ? min(fadeDuration, 0.55) : fadeDuration

        guard duration > 0 else {
            streetBedPlayer.volume = target.volume
            band.frequency = target.frequency
            return
        }

        streetBedTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let steps = 18

            for step in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64((duration / Double(steps)) * 1_000_000_000))
                guard !Task.isCancelled else { return }

                let progress = Float(step) / Float(steps)
                self.streetBedPlayer.volume = interpolate(from: startVolume, to: target.volume, progress: progress)
                band.frequency = interpolate(from: startFrequency, to: target.frequency, progress: progress)
            }
        }
    }

    func ensureStreetBedLoopStarted() {
        guard !streetBedPlayer.isPlaying else { return }
        guard let buffer = streetBedBuffer ?? loadPCMBuffer(for: .cityStreetBed) else { return }
        streetBedBuffer = buffer

        do {
            if !effectEngine.isRunning {
                try effectEngine.start()
            }
        } catch {
        }

        streetBedPlayer.stop()
        streetBedPlayer.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        streetBedPlayer.play()
    }

    func streetBedMix(for presence: StreetPresence) -> (volume: Float, frequency: Float) {
        switch presence {
        case .off:
            return (0.0, 650)
        case .insideClosedDoor:
            return (0.05, 850)
        case .insideOpenDoor:
            return (0.14, 2400)
        case .courtyard:
            return (0.18, 3200)
        case .outside:
            return (0.24, 18_000)
        case .wideOpenStreet:
            return (0.34, 18_000)
        }
    }
}
