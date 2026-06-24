import AVFoundation

extension AudioCoordinator {
    func configureAudioEngine() {
        effectEngine.attach(environmentNode)
        effectEngine.attach(effectReverb)
        effectEngine.attach(preStunMixer)
        effectEngine.attach(effectOnlyMixer)
        effectEngine.attach(stunReverb)
        effectEngine.attach(stunEQ)
        effectEngine.attach(streetBedPlayer)
        effectEngine.attach(streetBedEQ)

        // Get the engine's working format from environmentNode output.
        // CRITICAL: must use explicit format for all connections involving
        // effectOnlyMixer (no inputs yet → output format is nil with format: nil).
        let graphFormat = environmentNode.outputFormat(forBus: 0)

        // Spatial chain: environmentNode → effectReverb → preStunMixer (bus 0)
        // effectReverb only processes spatial sounds (doorbell, doorbanging, etc.)
        // and does NOT affect non-spatial sounds during normal play.
        effectEngine.connect(environmentNode, to: effectReverb, format: nil)
        effectEngine.connect(effectReverb, to: preStunMixer, fromBus: 0, toBus: 0, format: graphFormat)

        // Non-spatial chain: effectOnlyMixer → preStunMixer (bus 1)
        effectEngine.connect(effectOnlyMixer, to: preStunMixer, fromBus: 0, toBus: 1, format: graphFormat)

        // Combined: preStunMixer → stunReverb → stunEQ → mainMixer
        // stunReverb applies reverb to ALL sounds ONLY during stun effect.
        // During normal play, stunReverb.wetDryMix = 0 → no reverb on non-spatial sounds.
        effectEngine.connect(preStunMixer, to: stunReverb, format: graphFormat)
        effectEngine.connect(stunReverb, to: stunEQ, format: graphFormat)
        effectEngine.connect(stunEQ, to: effectEngine.mainMixerNode, format: graphFormat)

        // Street bed joins the stun chain so outdoor ambience is muffled too.
        effectEngine.connect(streetBedPlayer, to: streetBedEQ, format: nil)
        effectEngine.connect(streetBedEQ, to: preStunMixer, fromBus: 0, toBus: 2, format: nil)

        environmentNode.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
        environmentNode.reverbParameters.enable = false
        environmentNode.distanceAttenuationParameters.distanceAttenuationModel = .exponential
        environmentNode.distanceAttenuationParameters.referenceDistance = 3
        environmentNode.distanceAttenuationParameters.rolloffFactor = 1.2

        applyDefaultGlobalReverb()

        let band = streetBedEQ.bands[0]
        band.filterType = .lowPass
        band.bypass = false
        band.bandwidth = 0.5
        band.gain = 0
        band.frequency = 650
        streetBedPlayer.volume = 0

        let stunBand = stunEQ.bands[0]
        stunBand.filterType = .lowPass
        stunBand.bypass = true
        stunBand.bandwidth = 0.5
        stunBand.gain = 0
        stunBand.frequency = 20000

        // stunReverb: no reverb during normal play, only activated during stun
        stunReverb.loadFactoryPreset(.largeHall)
        stunReverb.wetDryMix = 0

        do {
            try effectEngine.start()
        } catch {
            print("[AudioEngine] FAILED to start: \(error.localizedDescription)")
        }
    }

    func activateAudioSessionIfNeeded() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
        }
        #endif
    }

    func applyDefaultGlobalReverb() {
        guard !isStunned else { return }
        effectReverb.loadFactoryPreset(Self.defaultGlobalReverbPreset)
        effectReverb.wetDryMix = Self.defaultGlobalReverbWetDryMix
    }

    func resourceURL(for cue: AudioCueID) -> URL? {
        if let url = Bundle.main.url(forResource: cue.resourceName, withExtension: cue.fileExtension, subdirectory: "Audio") {
            return url
        }

        if let bundled = Bundle.main.url(forResource: cue.resourceName, withExtension: cue.fileExtension) {
            return bundled
        }

        let workingDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let fallback = workingDirectoryURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
            .appendingPathComponent("\(cue.resourceName).\(cue.fileExtension)")

        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }

        // Try relative to the app bundle
        let appBundleURL = Bundle.main.bundleURL.deletingLastPathComponent()
        let appRelative = appBundleURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
            .appendingPathComponent("\(cue.resourceName).\(cue.fileExtension)")

        if FileManager.default.fileExists(atPath: appRelative.path) {
            return appRelative
        }

        // Try in the project directory
        let projectURL = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let projectRelative = projectURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Audio", isDirectory: true)
            .appendingPathComponent("\(cue.resourceName).\(cue.fileExtension)")

        return FileManager.default.fileExists(atPath: projectRelative.path) ? projectRelative : nil
    }

    func loadPCMBuffer(for cue: AudioCueID) -> AVAudioPCMBuffer? {
        guard let url = resourceURL(for: cue) else { return nil }

        do {
            let file = try AVAudioFile(forReading: url)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                return nil
            }

            try file.read(into: buffer)
            return buffer
        } catch {
            return nil
        }
    }

    func makePlayer(for cue: AudioCueID) -> AVAudioPlayer? {
        guard !isMuted, let url = resourceURL(for: cue) else { return nil }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = cue.defaultVolume
            player.numberOfLoops = cue.loops ? -1 : 0
            player.prepareToPlay()
            return player
        } catch {
            return nil
        }
    }

    func duration(of cue: AudioCueID) -> TimeInterval {
        if let cached = cueDurationCache[cue] {
            return cached
        }

        let duration: TimeInterval
        if let url = resourceURL(for: cue),
           let file = try? AVAudioFile(forReading: url) {
            duration = Double(file.length) / file.processingFormat.sampleRate
        } else {
            duration = 0
        }

        cueDurationCache[cue] = duration
        return duration
    }
}
