@preconcurrency import AVFoundation
import Foundation

@MainActor
extension StreetTrafficCoordinator {
    func makeTuning(for object: TrafficObject) -> TrafficEngineTuning {
        let idle = max(500, object.profile.idleEngineHz)
        let top = max(idle + 500, object.profile.maxEngineHz)
        let shift = min(top - 100, max(idle + 100, object.profile.gearShiftEngineHz))
        let gears = max(2, min(10, object.profile.gearCount))
        return TrafficEngineTuning(idleHz: idle, topHz: top, shiftHz: shift, gears: gears)
    }

    func makeAudioUnit(for object: TrafficObject, buffer: AVAudioPCMBuffer) throws -> TrafficAudioUnit {
        if !effectEngine.isRunning {
            try effectEngine.start()
        }

        let player = AVAudioPlayerNode()
        let brakePlayer = makeBrakePlayer()
        let varispeed = AVAudioUnitVarispeed()
        let eq = AVAudioUnitEQ(numberOfBands: 2)
        let panner = AVAudioMixerNode()

        configureEQ(eq, object: object)

        effectEngine.attach(player)
        if let brakePlayer {
            effectEngine.attach(brakePlayer)
        }
        effectEngine.attach(varispeed)
        effectEngine.attach(eq)
        effectEngine.attach(panner)

        effectEngine.connect(player, to: varispeed, format: buffer.format)
        if let brakePlayer, let brakeBuffer {
            effectEngine.connect(brakePlayer, to: panner, format: brakeBuffer.format)
        }
        effectEngine.connect(varispeed, to: eq, format: buffer.format)
        effectEngine.connect(eq, to: panner, format: buffer.format)
        effectEngine.connect(panner, to: effectEngine.mainMixerNode, format: nil)

        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        if let brakePlayer, let brakeBuffer {
            brakePlayer.scheduleBuffer(brakeBuffer, at: nil, options: [.loops], completionHandler: nil)
            brakePlayer.volume = 0
        }
        panner.pan = 0
        panner.outputVolume = 0
        return TrafficAudioUnit(player: player, brakePlayer: brakePlayer, varispeed: varispeed, eq: eq, panner: panner)
    }

    func configureEQ(_ eq: AVAudioUnitEQ, object: TrafficObject) {
        let lowBand = eq.bands[0]
        lowBand.bypass = false
        lowBand.filterType = .parametric
        lowBand.bandwidth = 1.1
        switch object.profile.cue {
        case .trafficEngineLight:
            lowBand.frequency = 220
            lowBand.gain = -2
        case .trafficEngineSedan:
            lowBand.frequency = 260
            lowBand.gain = 2
        case .trafficEngineSport:
            lowBand.frequency = 320
            lowBand.gain = 1
        case .trafficEngineCoupe:
            lowBand.frequency = 285
            lowBand.gain = 1
        case .trafficEngineRoadster:
            lowBand.frequency = 300
            lowBand.gain = 0
        default:
            lowBand.frequency = 250
            lowBand.gain = 1
        }

        let highBand = eq.bands[1]
        highBand.bypass = false
        highBand.filterType = .highShelf
        highBand.frequency = 2400
        highBand.bandwidth = 0.9
        switch object.profile.cue {
        case .trafficEngineLight:
            highBand.gain = 4
        case .trafficEngineSedan:
            highBand.gain = -2
        case .trafficEngineSport:
            highBand.gain = 3
        case .trafficEngineCoupe:
            highBand.gain = 1
        case .trafficEngineRoadster:
            highBand.gain = 4
        default:
            highBand.gain = 1
        }
    }

    func stopAndDetach(_ audio: TrafficAudioUnit) {
        audio.player.stop()
        audio.brakePlayer?.stop()
        effectEngine.detach(audio.player)
        if let brakePlayer = audio.brakePlayer {
            effectEngine.detach(brakePlayer)
        }
        effectEngine.detach(audio.varispeed)
        effectEngine.detach(audio.eq)
        effectEngine.detach(audio.panner)
    }

    func makeBrakePlayer() -> AVAudioPlayerNode? {
        if brakeBuffer == nil {
            brakeBuffer = loadPCMBuffer(for: .trafficBrakeSoft)
        }
        guard brakeBuffer != nil else { return nil }
        return AVAudioPlayerNode()
    }

    func loadPCMBuffer(for cue: AudioCueID) -> AVAudioPCMBuffer? {
        guard let url = resourceURLProvider(cue) else { return nil }

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

    func adjustedSpeedRate(base: Float, speedBand: TrafficSpeedBand, routeStyle: TrafficRouteStyle) -> Float {
        let bandMultiplier: Float
        switch speedBand {
        case .slow:
            bandMultiplier = 0.62
        case .normal:
            bandMultiplier = 1.0
        case .fast:
            bandMultiplier = 1.42
        }

        let routeMultiplier: Float
        switch routeStyle {
        case .roadPass:
            routeMultiplier = 1.0
        case .slowRollBy:
            routeMultiplier = 0.9
        case .courtyardParking:
            routeMultiplier = 0.74
        }

        return max(0.48, min(1.75, base * bandMultiplier * routeMultiplier))
    }

    func advanceSpeed(
        current: Float,
        target: Float,
        maxSpeed: Float,
        acceleration: Float,
        braking: Float,
        rolling: Float,
        drag: Float,
        deltaTime: Float
    ) -> Float {
        let delta = target - current
        let gasMix = max(0, min(1, delta / max(1.0, target)))
        let brakeMix = max(0, min(1, (-delta) / max(1.0, current)))
        let gasAccel = acceleration * gasMix
        let brakeDecel = braking * brakeMix
        let dragDecel = drag * current
        var next = current + (gasAccel - brakeDecel - rolling - dragDecel) * deltaTime

        if target < 0.2, next < 0.8 {
            next = max(0, next - 2.4 * deltaTime)
        }

        return min(maxSpeed, max(0, next))
    }

    func trafficBrakeSoundVolume(
        for object: TrafficObject,
        speed: Float,
        previousSpeed: Float,
        deltaTime: Float,
        isParked: Bool,
        didCompleteParkingStop: Bool
    ) -> Float {
        guard object.routeStyle == .courtyardParking || object.routeStyle == .slowRollBy else {
            return 0
        }

        let braking = max(0, previousSpeed - speed) / max(0.01, deltaTime)
        let brakingMix = min(1.0, braking / max(0.8, object.brakeDeceleration * 0.7))
        let speedMix = min(1.0, speed / max(1.1, object.cruiseSpeed * 0.4))
        var volume = brakingMix * (0.07 + 0.2 * speedMix) * max(0.72, object.profile.brakeScale)

        if object.routeStyle == .courtyardParking, !isParked {
            let parkingApproachMix = 1 - min(1.0, abs(speed - object.brakeTargetSpeed) / max(0.4, object.cruiseSpeed * 0.28))
            volume *= 1 + (parkingApproachMix * 0.28)
        }

        if didCompleteParkingStop {
            volume *= 0.22
        }
        if isParked {
            volume *= 0.06
        }
        if brakingMix < 0.12 || speed < max(0.42, object.brakeTargetSpeed * 0.72) {
            return 0
        }

        return min(0.26, volume)
    }

    func engineRate(
        for object: TrafficObject,
        speedNorm: Float,
        speed: Float,
        previousSpeed: Float,
        deltaTime: Float,
        tuning: TrafficEngineTuning,
        elapsedTime: Float,
        previousGear: inout Int,
        shiftPulseUntil: inout Float
    ) -> Float {
        let speedAudioProgress = pow(Double(speedNorm), 0.56)
        let hzRange = tuning.topHz - tuning.idleHz
        var targetHz = tuning.idleHz + hzRange * speedAudioProgress

        let gear = currentGear(speedNorm: speedNorm, gears: tuning.gears)
        if gear > previousGear {
            shiftPulseUntil = elapsedTime + 0.055
        }
        previousGear = gear

        let pulseRemaining = max(0, shiftPulseUntil - elapsedTime)
        let shiftMix = min(1.0, pulseRemaining / 0.055)
        if shiftMix > 0 {
            let smoothMix = shiftMix * shiftMix * (3 - 2 * shiftMix)
            let deltaToShift = tuning.shiftHz - targetHz
            let maxShiftDelta = hzRange * 0.014
            let clampedDelta = min(maxShiftDelta, max(-maxShiftDelta, deltaToShift))
            targetHz += clampedDelta * Double(smoothMix)
        }

        let acceleration = max(0, speed - previousSpeed) / max(0.01, deltaTime)
        let braking = max(0, previousSpeed - speed) / max(0.01, deltaTime)
        let accelMix = min(1.0, Double(acceleration / max(1.6, object.acceleration)))
        let brakeMix = min(1.0, Double(braking / max(1.6, object.brakeDeceleration)))
        targetHz += hzRange * 0.11 * accelMix
        targetHz -= hzRange * 0.08 * brakeMix

        let breathing = sin(Double(elapsedTime) * Double.pi * 1.2 + Double(object.id.hashValue & 15))
        let breathingAmount: Double
        switch object.profile.cue {
        case .trafficEngineLight:
            breathingAmount = 82
        case .trafficEngineSedan:
            breathingAmount = 72
        case .trafficEngineSport:
            breathingAmount = 95
        case .trafficEngineCoupe:
            breathingAmount = 80
        case .trafficEngineRoadster:
            breathingAmount = 102
        default:
            breathingAmount = 70
        }

        targetHz += breathing * breathingAmount
        if object.profile.cue == .trafficEngineLight {
            targetHz += hzRange * 0.028
        }
        targetHz += Double(object.toneOffset) * 160
        targetHz = min(tuning.topHz, max(tuning.idleHz * 0.88, targetHz))
        return clampRate(targetHz / max(1, object.sampleRate))
    }

    func currentGear(speedNorm: Float, gears: Int) -> Int {
        let clamped = min(1.0, max(0.0, Double(speedNorm)))
        return min(gears, max(1, Int(clamped * Double(gears)) + 1))
    }

    func smoothRate(previousRate: Float, targetRate: Float, routeStyle: TrafficRouteStyle) -> Float {
        let tau: Float
        switch routeStyle {
        case .roadPass:
            tau = 0.09
        case .slowRollBy:
            tau = 0.11
        case .courtyardParking:
            tau = 0.14
        }

        let deltaTime: Float = 0.08
        let alpha = 1.0 - exp(-deltaTime / max(0.01, tau))
        return clampRate(Double(previousRate + (targetRate - previousRate) * alpha))
    }

    func clampRate(_ raw: Double) -> Float {
        Float(min(3.2, max(0.45, raw)))
    }
}
