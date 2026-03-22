@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AudioCoordinator {
    private static let defaultGlobalReverbPreset: AVAudioUnitReverbPreset = .largeHall
    private static let defaultGlobalReverbWetDryMix: Float = 46

    enum StreetPresence: Equatable {
        case off
        case insideClosedDoor
        case insideOpenDoor
        case outside
    }

    private struct SpatialEffectStyle {
        let position: AVAudio3DPoint
        let reverbBlend: Float
        let reverbPreset: AVAudioUnitReverbPreset
        let wetDryMix: Float
        let volumeMultiplier: Float
    }

    private let isMuted: Bool
    private let effectEngine = AVAudioEngine()
    private let environmentNode = AVAudioEnvironmentNode()
    private let effectReverb = AVAudioUnitReverb()
    private let streetBedPlayer = AVAudioPlayerNode()
    private let streetBedEQ = AVAudioUnitEQ(numberOfBands: 1)

    private var ambientPlayer: AVAudioPlayer?
    private var activeEffects: [AVAudioPlayer] = []
    private var activeSpatialPlayers: [AVAudioPlayerNode] = []
    private var ambientCue: AudioCueID?
    private var currentStepSurface: StepSurface = .carpet
    private var lastAsphaltStep: AudioCueID?
    private var streetBedBuffer: AVAudioPCMBuffer?
    private var streetPresence: StreetPresence = .off
    private var streetBedTransitionTask: Task<Void, Never>?
    private var streetTraffic: StreetTrafficCoordinator?

    init(isMuted: Bool = false) {
        self.isMuted = isMuted
        activateAudioSessionIfNeeded()
        configureAudioEngine()
        streetTraffic = StreetTrafficCoordinator(
            effectEngine: effectEngine,
            resourceURLProvider: { [weak self] cue in
                self?.resourceURL(for: cue)
            }
        )
    }

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

    func setStepSurface(_ surface: StepSurface) {
        currentStepSurface = surface
    }

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

    func setTrafficEnabled(_ enabled: Bool) {
        guard !isMuted else { return }
        streetTraffic?.setEnabled(enabled)
    }

    func setStreetListenerPosition(_ position: GridPosition) {
        streetTraffic?.setListenerStreetPosition(position)
    }

    func triggerStreetCarDeparture(_ id: UUID) {
        streetTraffic?.triggerDeparture(for: id)
    }

    func setStreetCarObserver(_ observer: (([StreetTrafficCoordinator.StreetCarSnapshot]) -> Void)?) {
        streetTraffic?.onStreetCarsChanged = observer
    }

    func setStreetParkingObserver(_ observer: ((StreetTrafficCoordinator.StreetCarSnapshot) -> Void)?) {
        streetTraffic?.onStreetCarParked = observer
    }

    func runStreetDebugScenario(_ rawName: String) -> Bool {
        guard let scenario = StreetTrafficCoordinator.DebugScenario(rawValue: rawName) else {
            return false
        }

        streetTraffic?.runDebugScenario(scenario)
        return true
    }

    func clearStreetDebugScenario() {
        streetTraffic?.clearDebugScenario()
    }

    func streetDebugSnapshotPayload() -> [[String: Any]] {
        streetTraffic?.debugSnapshotPayload() ?? []
    }

    func playStep(surfaceOverride: StepSurface? = nil) {
        guard !isMuted else { return }
        let surface = surfaceOverride ?? currentStepSurface

        switch surface {
        case .carpet:
            let cue: AudioCueID = Bool.random() ? .stepCarpet01 : .stepCarpet02
            playEffect(cue)
        case .asphalt:
            let cues: [AudioCueID] = [.stepAsphalt01, .stepAsphalt02, .stepAsphalt03, .stepAsphalt04, .stepAsphalt05]
            let available = cues.filter { $0 != lastAsphaltStep }
            let cue = available.randomElement() ?? .stepAsphalt01
            lastAsphaltStep = cue
            playEffect(cue)
        }
    }

    func playBlockedMovement() {
        guard !isMuted else { return }
        playEffect(.obstacleThud)
    }

    func playEffect(_ cue: AudioCueID?) {
        guard !isMuted else { return }
        guard let cue, let url = resourceURL(for: cue) else { return }
        activeEffects.removeAll { !$0.isPlaying }

        if let style = spatialStyle(for: cue) {
            playSpatialEffect(cue, url: url, style: style)
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = cue.defaultVolume
            player.prepareToPlay()
            player.play()
            activeEffects.append(player)
        } catch {
        }
    }

    private func resourceURL(for cue: AudioCueID) -> URL? {
        if let url = Bundle.main.url(forResource: cue.resourceName, withExtension: cue.fileExtension, subdirectory: "Audio") {
            return url
        }

        return Bundle.main.url(forResource: cue.resourceName, withExtension: cue.fileExtension)
    }

    private func configureAudioEngine() {
        effectEngine.attach(environmentNode)
        effectEngine.attach(effectReverb)
        effectEngine.attach(streetBedPlayer)
        effectEngine.attach(streetBedEQ)

        effectEngine.connect(environmentNode, to: effectReverb, format: nil)
        effectEngine.connect(effectReverb, to: effectEngine.mainMixerNode, format: nil)
        effectEngine.connect(streetBedPlayer, to: streetBedEQ, format: nil)
        effectEngine.connect(streetBedEQ, to: effectEngine.mainMixerNode, format: nil)

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

        do {
            try effectEngine.start()
        } catch {
        }
    }

    private func activateAudioSessionIfNeeded() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
        }
        #endif
    }

    private func ensureStreetBedLoopStarted() {
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

    private func loadPCMBuffer(for cue: AudioCueID) -> AVAudioPCMBuffer? {
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

    private func streetBedMix(for presence: StreetPresence) -> (volume: Float, frequency: Float) {
        switch presence {
        case .off:
            return (0.0, 650)
        case .insideClosedDoor:
            return (0.05, 850)
        case .insideOpenDoor:
            return (0.14, 2400)
        case .outside:
            return (0.24, 18_000)
        }
    }

    private func spatialStyle(for cue: AudioCueID) -> SpatialEffectStyle? {
        switch cue {
        case .doorbellMain:
            return SpatialEffectStyle(
                position: AVAudio3DPoint(x: -8, y: 0, z: -10),
                reverbBlend: 95,
                reverbPreset: .largeHall,
                wetDryMix: 76,
                volumeMultiplier: 0.92
            )
        case .doorBangingHard:
            return SpatialEffectStyle(
                position: AVAudio3DPoint(x: 7, y: 0, z: -9),
                reverbBlend: 92,
                reverbPreset: .largeHall,
                wetDryMix: 80,
                volumeMultiplier: 0.95
            )
        case .doorBreakHeavy:
            return SpatialEffectStyle(
                position: AVAudio3DPoint(x: 4, y: 0, z: -10),
                reverbBlend: 94,
                reverbPreset: .cathedral,
                wetDryMix: 90,
                volumeMultiplier: 1.08
            )
        case .punchHit:
            return SpatialEffectStyle(
                position: AVAudio3DPoint(x: 1, y: 0, z: -2),
                reverbBlend: 35,
                reverbPreset: .mediumRoom,
                wetDryMix: 24,
                volumeMultiplier: 1.0
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

    private func fadeOutAndStop(_ player: AVAudioPlayer?, duration: TimeInterval) {
        guard let player else { return }
        player.setVolume(0, fadeDuration: duration)

        Task { @MainActor in
            let nanoseconds = UInt64(duration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            player.stop()
        }
    }

    private func applyDefaultGlobalReverb() {
        effectReverb.loadFactoryPreset(Self.defaultGlobalReverbPreset)
        effectReverb.wetDryMix = Self.defaultGlobalReverbWetDryMix
    }
}

private func interpolate(from start: Float, to end: Float, progress: Float) -> Float {
    start + ((end - start) * progress)
}

private func normalized(_ value: Float, start: Float, end: Float) -> Float {
    guard end > start else { return 1.0 }
    return min(1.0, max(0.0, (value - start) / (end - start)))
}
