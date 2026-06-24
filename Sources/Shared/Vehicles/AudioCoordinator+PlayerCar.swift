@preconcurrency import AVFoundation
import Foundation

private struct PlayerCarEngineTuning {
    let idleHz: Double
    let topHz: Double
    let shiftHz: Double
    let gears: Int
}

private struct PlayerCarAudioUnit {
    let player: AVAudioPlayerNode
    let varispeed: AVAudioUnitVarispeed
    let eq: AVAudioUnitEQ
    let panner: AVAudioMixerNode
    let sampleRate: Double
    let tuning: PlayerCarEngineTuning
}

@MainActor
final class PlayerCarAudioRuntime {
    fileprivate var controlledCarAudio: PlayerCarAudioUnit?
    var controlledCarBrakePlayer: AVAudioPlayer?
    var controlledCarStartupPlayer: AVAudioPlayer?
    var controlledCarCurrentRate: Float = 1
    var controlledCarLastGear = 1
    var controlledCarShiftPulseUntil: TimeInterval = 0
    var controlledCarLastRateUpdateTime: TimeInterval?
}

extension AudioCoordinator {
    fileprivate var controlledCarAudio: PlayerCarAudioUnit? {
        get { playerCarAudioRuntime.controlledCarAudio }
        set { playerCarAudioRuntime.controlledCarAudio = newValue }
    }

    var controlledCarBrakePlayer: AVAudioPlayer? {
        get { playerCarAudioRuntime.controlledCarBrakePlayer }
        set { playerCarAudioRuntime.controlledCarBrakePlayer = newValue }
    }

    var controlledCarStartupPlayer: AVAudioPlayer? {
        get { playerCarAudioRuntime.controlledCarStartupPlayer }
        set { playerCarAudioRuntime.controlledCarStartupPlayer = newValue }
    }

    var controlledCarCurrentRate: Float {
        get { playerCarAudioRuntime.controlledCarCurrentRate }
        set { playerCarAudioRuntime.controlledCarCurrentRate = newValue }
    }

    var controlledCarLastGear: Int {
        get { playerCarAudioRuntime.controlledCarLastGear }
        set { playerCarAudioRuntime.controlledCarLastGear = newValue }
    }

    var controlledCarShiftPulseUntil: TimeInterval {
        get { playerCarAudioRuntime.controlledCarShiftPulseUntil }
        set { playerCarAudioRuntime.controlledCarShiftPulseUntil = newValue }
    }

    var controlledCarLastRateUpdateTime: TimeInterval? {
        get { playerCarAudioRuntime.controlledCarLastRateUpdateTime }
        set { playerCarAudioRuntime.controlledCarLastRateUpdateTime = newValue }
    }

    func playPlayerCarDoorOpen() {
        playEffect(.playerCarDoorOpen)
    }

    func playPlayerCarDoorClose() {
        playEffect(.playerCarDoorClose)
    }

    func playerCarDoorOpenDuration() -> TimeInterval {
        duration(of: .playerCarDoorOpen)
    }

    func playerCarDoorCloseDuration() -> TimeInterval {
        duration(of: .playerCarDoorClose)
    }

    func activateControlledCarAudio(for blueprint: DriveableVehicleBlueprint) {
        guard !isMuted else { return }
        stopControlledCarAudio()

        guard let buffer = loadPCMBuffer(for: blueprint.engineCue) else { return }

        do {
            if !effectEngine.isRunning {
                try effectEngine.start()
            }

            let player = AVAudioPlayerNode()
            let varispeed = AVAudioUnitVarispeed()
            let eq = AVAudioUnitEQ(numberOfBands: 2)
            let panner = AVAudioMixerNode()

            configureControlledCarEQ(eq, kind: blueprint.kind)

            effectEngine.attach(player)
            effectEngine.attach(varispeed)
            effectEngine.attach(eq)
            effectEngine.attach(panner)

            effectEngine.connect(player, to: varispeed, format: buffer.format)
            effectEngine.connect(varispeed, to: eq, format: buffer.format)
            effectEngine.connect(eq, to: panner, format: buffer.format)
            effectEngine.connect(panner, to: preStunMixer, format: nil)

            player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
            panner.pan = 0
            panner.outputVolume = 1
            player.play()

            let tuning = PlayerCarEngineTuning(
                idleHz: max(500, blueprint.idleEngineHz),
                topHz: max(blueprint.idleEngineHz + 500, blueprint.maxEngineHz),
                shiftHz: min(blueprint.maxEngineHz - 100, max(blueprint.idleEngineHz + 100, blueprint.gearShiftEngineHz)),
                gears: max(2, min(10, blueprint.gearCount))
            )

            controlledCarAudio = PlayerCarAudioUnit(
                player: player,
                varispeed: varispeed,
                eq: eq,
                panner: panner,
                sampleRate: buffer.format.sampleRate,
                tuning: tuning
            )
            controlledCarCurrentRate = clampControlledCarRate(tuning.idleHz / buffer.format.sampleRate)
            controlledCarLastGear = 1
            controlledCarShiftPulseUntil = 0
            controlledCarLastRateUpdateTime = nil
            varispeed.rate = controlledCarCurrentRate

            if controlledCarBrakePlayer == nil,
               let brakeURL = resourceURL(for: .playerCarBrake) ?? resourceURL(for: .trafficBrakeSoft),
               let brakePlayer = try? AVAudioPlayer(contentsOf: brakeURL) {
                brakePlayer.numberOfLoops = -1
                brakePlayer.volume = 0
                brakePlayer.prepareToPlay()
                controlledCarBrakePlayer = brakePlayer
            }
        } catch {
            controlledCarAudio = nil
        }
    }

    @discardableResult
    func playControlledCarStartup(_ cue: AudioCueID) -> TimeInterval {
        guard !isMuted else { return 0 }
        guard let url = resourceURL(for: cue) else { return 0 }

        controlledCarStartupPlayer?.stop()
        controlledCarStartupPlayer = try? AVAudioPlayer(contentsOf: url)
        controlledCarStartupPlayer?.volume = cue.defaultVolume
        controlledCarStartupPlayer?.prepareToPlay()
        controlledCarStartupPlayer?.play()
        return controlledCarStartupPlayer?.duration ?? duration(of: cue)
    }

    func updateControlledCarAudio(
        speed: Double,
        maxSpeed: Double,
        gasPressed: Bool,
        brakePressed: Bool,
        elapsedTime: TimeInterval,
        lanePan: Float
    ) {
        guard !isMuted else { return }
        guard let unit = controlledCarAudio else { return }

        let targetRate = controlledCarEngineRate(
            speed: speed,
            maxSpeed: maxSpeed,
            tuning: unit.tuning,
            elapsedTime: elapsedTime,
            gasPressed: gasPressed,
            brakePressed: brakePressed
        )
        let deltaTime = controlledCarDeltaTime(elapsedTime: elapsedTime)
        controlledCarCurrentRate = smoothControlledCarRate(
            current: controlledCarCurrentRate,
            target: targetRate,
            deltaTime: deltaTime,
            isUnderInput: gasPressed || brakePressed
        )
        unit.varispeed.rate = controlledCarCurrentRate
        unit.panner.pan = max(-1, min(1, lanePan))
        updateControlledCarBrake(speed: speed, brakePressed: brakePressed)
    }

    func stopControlledCarAudio() {
        controlledCarStartupPlayer?.stop()
        controlledCarStartupPlayer = nil
        controlledCarBrakePlayer?.stop()
        controlledCarBrakePlayer = nil

        guard let unit = controlledCarAudio else { return }
        unit.player.stop()
        effectEngine.detach(unit.player)
        effectEngine.detach(unit.varispeed)
        effectEngine.detach(unit.eq)
        effectEngine.detach(unit.panner)
        controlledCarAudio = nil
        controlledCarCurrentRate = 1
        controlledCarLastGear = 1
        controlledCarShiftPulseUntil = 0
        controlledCarLastRateUpdateTime = nil
    }

    private func configureControlledCarEQ(_ eq: AVAudioUnitEQ, kind: DriveableVehicleKind) {
        let lowBand = eq.bands[0]
        lowBand.bypass = false
        lowBand.filterType = .parametric
        lowBand.bandwidth = 1.1

        let highBand = eq.bands[1]
        highBand.bypass = false
        highBand.filterType = .highShelf
        highBand.frequency = 2_400
        highBand.bandwidth = 0.9

        switch kind {
        case .light:
            lowBand.frequency = 220
            lowBand.gain = -2
            highBand.gain = 4
        case .sedan:
            lowBand.frequency = 260
            lowBand.gain = 2
            highBand.gain = -2
        case .sport:
            lowBand.frequency = 320
            lowBand.gain = 1
            highBand.gain = 3
        case .coupe:
            lowBand.frequency = 285
            lowBand.gain = 1
            highBand.gain = 1
        case .roadster:
            lowBand.frequency = 300
            lowBand.gain = 0
            highBand.gain = 4
        }
    }

    private func controlledCarEngineRate(
        speed: Double,
        maxSpeed: Double,
        tuning: PlayerCarEngineTuning,
        elapsedTime: TimeInterval,
        gasPressed: Bool,
        brakePressed: Bool
    ) -> Float {
        let clampedSpeed = max(0, abs(speed))
        let speedNorm = maxSpeed > 0 ? min(1.0, max(0.0, clampedSpeed / maxSpeed)) : 0
        let speedAudioProgress = pow(speedNorm, 0.56)
        let hzRange = tuning.topHz - tuning.idleHz
        let targetHz = tuning.idleHz + hzRange * speedAudioProgress

        let gear = min(tuning.gears, max(1, Int(speedNorm * Double(tuning.gears)) + 1))
        if gear > controlledCarLastGear {
            controlledCarShiftPulseUntil = elapsedTime + 0.055
        }
        controlledCarLastGear = gear

        let pulseRemaining = max(0, controlledCarShiftPulseUntil - elapsedTime)
        let shiftMix = min(1.0, pulseRemaining / 0.055)
        var hz = targetHz
        if shiftMix > 0 {
            let smoothMix = shiftMix * shiftMix * (3 - 2 * shiftMix)
            let deltaToShift = tuning.shiftHz - targetHz
            let maxShiftDelta = hzRange * 0.014
            let clampedDelta = min(maxShiftDelta, max(-maxShiftDelta, deltaToShift))
            hz = targetHz + clampedDelta * smoothMix
        }

        if gasPressed {
            hz += hzRange * 0.028
        }
        if brakePressed {
            hz -= hzRange * 0.035
        }

        hz = min(tuning.topHz, max(tuning.idleHz * 0.88, hz))
        return clampControlledCarRate(hz / max(1, controlledCarAudio?.sampleRate ?? tuning.idleHz))
    }

    private func controlledCarDeltaTime(elapsedTime: TimeInterval) -> TimeInterval {
        guard let last = controlledCarLastRateUpdateTime, elapsedTime >= last else {
            controlledCarLastRateUpdateTime = elapsedTime
            return 1.0 / 60.0
        }

        controlledCarLastRateUpdateTime = elapsedTime
        return min(0.12, max(1.0 / 240.0, elapsedTime - last))
    }

    private func smoothControlledCarRate(
        current: Float,
        target: Float,
        deltaTime: TimeInterval,
        isUnderInput: Bool
    ) -> Float {
        let tau: TimeInterval = isUnderInput ? 0.045 : 0.08
        let alpha = Float(1.0 - exp(-deltaTime / max(0.01, tau)))
        let next = current + (target - current) * alpha
        return clampControlledCarRate(Double(next))
    }

    private func clampControlledCarRate(_ raw: Double) -> Float {
        Float(min(3.2, max(0.45, raw)))
    }

    private func updateControlledCarBrake(speed: Double, brakePressed: Bool) {
        guard let brakePlayer = controlledCarBrakePlayer else { return }
        let playerSpeed = abs(speed)
        let shouldPlay = brakePressed && playerSpeed > 4

        if shouldPlay {
            if !brakePlayer.isPlaying {
                brakePlayer.currentTime = 0
                brakePlayer.play()
            }
            brakePlayer.volume = Float(min(1.0, max(0.18, playerSpeed / 70.0)))
        } else {
            brakePlayer.volume = 0
            brakePlayer.stop()
        }
    }
}
