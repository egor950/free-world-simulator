@preconcurrency import AVFoundation
import Foundation
import GameplayKit

@MainActor
extension StreetTrafficCoordinator {
    func startLoop() {
        trafficLoopTask?.cancel()
        cleanupFinishedTraffic()
        guard activeDebugScenario == nil else { return }
        while activeTrafficPlayers.count < Self.desiredMinimumTrafficCount {
            spawnTrafficPass()
        }
        trafficLoopTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while self.isEnabled {
                if self.activeDebugScenario != nil {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    continue
                }

                self.cleanupFinishedTraffic()

                if self.activeTrafficPlayers.count < Self.desiredMinimumTrafficCount {
                    self.spawnTrafficPass()
                    continue
                }

                try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.2...0.45) * 1_000_000_000))
                guard !Task.isCancelled, self.isEnabled else { return }
                self.cleanupFinishedTraffic()

                if self.activeTrafficPlayers.count >= Self.maximumTrafficCount {
                    continue
                }

                self.spawnTrafficPass()
            }
        }
    }

    func stopLoop() {
        trafficLoopTask?.cancel()
        trafficLoopTask = nil
        activeStreetCarSnapshots = [:]
        forcedDepartureIDs.removeAll()
        lastCourtyardParkingCue = nil
        parkingSpawnDirector.reset(initiallyReady: false)

        for task in activeTrafficTasks.values {
            task.cancel()
        }
        activeTrafficTasks.removeAll()
        activeTrafficRoutes.removeAll()
        activeTrafficCues.removeAll()
        activeTrafficSpeedBands.removeAll()
        activeCourtyardParkingIDs.removeAll()

        for audio in activeTrafficPlayers.values {
            stopAndDetach(audio)
        }
        activeTrafficPlayers.removeAll()
    }

    func cleanupFinishedTraffic() {
        let finishedIDs = activeTrafficPlayers.compactMap { id, audio in
            audio.player.isPlaying ? nil : id
        }

        for id in finishedIDs {
            if let audio = activeTrafficPlayers.removeValue(forKey: id) {
                activeTrafficRoutes.removeValue(forKey: id)
                activeTrafficCues.removeValue(forKey: id)
                activeTrafficSpeedBands.removeValue(forKey: id)
                activeCourtyardParkingIDs.remove(id)
                clearStreetCarSnapshot(for: id)
                stopAndDetach(audio)
            }
        }

        parkingSpawnDirector.update(
            now: Date(),
            hasActiveParkingRoute: !activeCourtyardParkingIDs.isEmpty
        )
    }

    func runDebugScenarioInternal(_ scenario: DebugScenario) {
        let profile = trafficProfiles.first(where: { $0.cue == .trafficEngineLight }) ?? trafficProfiles[0]
        let buffer = trafficBufferCache[profile.cue] ?? loadPCMBuffer(for: profile.cue)
        guard let buffer else { return }
        trafficBufferCache[profile.cue] = buffer

        let object = makeDebugTrafficObject(for: scenario, profile: profile, sampleRate: buffer.format.sampleRate)
        parkingSpawnDirector.markParkingRouteStarted(at: Date())
        startTrafficObject(object, buffer: buffer)
    }

    func startTrafficObject(_ object: TrafficObject, buffer: AVAudioPCMBuffer) {
        do {
            let audio = try makeAudioUnit(for: object, buffer: buffer)
            let tuning = makeTuning(for: object)

            audio.panner.pan = trafficPan(for: object, x: object.startX, z: object.roadZ)
            audio.panner.outputVolume = 0
            audio.varispeed.rate = clampRate(tuning.idleHz / max(1, object.sampleRate))
            audio.player.play()
            audio.brakePlayer?.play()
            activeTrafficPlayers[object.id] = audio
            activeTrafficRoutes[object.id] = object.routeStyle
            activeTrafficCues[object.id] = object.profile.cue
            activeTrafficSpeedBands[object.id] = object.speedBand
            if object.routeStyle == .courtyardParking {
                self.activeCourtyardParkingIDs.insert(object.id)
            }

            let motionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                guard let audio = self.activeTrafficPlayers[object.id] else { return }

                let baseTick: UInt64 = 80_000_000
                var x = object.startX
                var z = object.startZ
                var speed = object.entrySpeed
                var previousSpeed = speed
                var elapsed: Float = 0
                let lifecycle = TrafficLifecycle(routeStyle: object.routeStyle, startPhase: object.startPhase)
                var currentRate = clampRate(tuning.idleHz / max(1, object.sampleRate))
                var previousGear = 1
                var shiftPulseUntil: Float = 0
                var lastStepTimestamp = ProcessInfo.processInfo.systemUptime

                while true {
                    guard !Task.isCancelled, audio.player.isPlaying else { break }

                    let currentTimestamp = ProcessInfo.processInfo.systemUptime
                    let dt = Float(min(0.4, max(0.04, currentTimestamp - lastStepTimestamp)))
                    lastStepTimestamp = currentTimestamp
                    elapsed += dt
                    lifecycle.advance(deltaTime: dt, parkHoldDuration: object.parkHoldDuration)
                    lifecycle.forceDepartureIfNeeded(for: object.id, forcedIDs: &self.forcedDepartureIDs, deltaTime: dt)

                    let targetSpeed: Float
                    if object.routeStyle == .courtyardParking {
                        targetSpeed = self.desiredCourtyardRouteSpeed(
                            for: object,
                            position: OutdoorWorldPoint(x: x, z: z),
                            lifecycle: lifecycle
                        )
                    } else {
                        targetSpeed = desiredSpeed(
                            for: object,
                            x: x,
                            z: z,
                            isParked: lifecycle.isParked,
                            parkedElapsed: lifecycle.parkedElapsed,
                            didCompleteParkingStop: lifecycle.didCompleteParkingStop,
                            departureElapsed: lifecycle.departureElapsed
                        )
                    }
                    speed = advanceSpeed(
                        current: speed,
                        target: targetSpeed,
                        maxSpeed: object.maxSpeed,
                        acceleration: object.acceleration,
                        braking: object.brakeDeceleration,
                        rolling: object.rollingDeceleration,
                        drag: object.dragFactor,
                        deltaTime: dt
                    )

                    if object.routeStyle == .courtyardParking {
                        let nextPoint = self.advanceCourtyardRoutePosition(
                            for: object,
                            current: OutdoorWorldPoint(x: x, z: z),
                            speed: speed,
                            lifecycle: lifecycle,
                            deltaTime: dt
                        )
                        x = nextPoint.x
                        z = nextPoint.z
                    } else if !lifecycle.isParked {
                        let direction: Float = object.directionLeftToRight ? 1 : -1
                        x += direction * speed * dt
                        z = trafficZ(for: object, x: x, isParked: lifecycle.isParked)
                    }

                    audio.panner.pan = self.trafficPan(for: object, x: x, z: z)
                    audio.panner.outputVolume = self.trafficVolume(for: object, x: x, z: z, speed: speed, isParked: lifecycle.isParked)
                    audio.brakePlayer?.volume = self.trafficBrakeSoundVolume(
                        for: object,
                        speed: speed,
                        previousSpeed: previousSpeed,
                        deltaTime: dt,
                        isParked: lifecycle.isParked,
                        didCompleteParkingStop: lifecycle.didCompleteParkingStop
                    )
                    if object.routeStyle != .courtyardParking {
                        self.updateStreetCarSnapshot(for: object, x: x, z: z, isParked: false, isLeaving: false)
                    }

                    let speedNorm = min(1.0, max(0.0, speed / max(0.1, object.maxSpeed)))
                    let targetRate = engineRate(
                        for: object,
                        speedNorm: speedNorm,
                        speed: speed,
                        previousSpeed: previousSpeed,
                        deltaTime: dt,
                        tuning: tuning,
                        elapsedTime: elapsed,
                        previousGear: &previousGear,
                        shiftPulseUntil: &shiftPulseUntil
                    )
                    currentRate = smoothRate(previousRate: currentRate, targetRate: targetRate, routeStyle: object.routeStyle)
                    audio.varispeed.rate = currentRate

                    if lifecycle.isParkingRoute {
                        if lifecycle.isStreetDeparture {
                            self.activeCourtyardParkingIDs.remove(object.id)
                        }
                        let reachedParkingSpot = self.hasReachedCourtyardParkingStop(
                            for: object,
                            position: OutdoorWorldPoint(x: x, z: z),
                            speed: speed,
                            previousSpeed: previousSpeed,
                            elapsed: elapsed
                        )
                        if reachedParkingSpot, lifecycle.beginParked() {
                            if let parkingPoint = object.courtyardAccessPlan?.parkingPoint {
                                x = parkingPoint.x
                                z = parkingPoint.z
                            }
                            speed = 0
                            previousSpeed = 0
                            audio.panner.pan = self.trafficPan(for: object, x: x, z: z)
                            audio.panner.outputVolume = self.trafficVolume(for: object, x: x, z: z, speed: speed, isParked: true)
                            audio.brakePlayer?.volume = 0
                            self.updateStreetCarSnapshot(for: object, x: x, z: z, isParked: true, isLeaving: false)
                            if let snapshot = self.activeStreetCarSnapshots[object.id] {
                                self.onStreetCarParked?(snapshot)
                            }
                        }

                        self.syncCourtyardParkingSnapshot(for: object, x: x, z: z, lifecycle: lifecycle)
                    }

                    if self.hasCompletedRoute(for: object, x: x, z: z, lifecycle: lifecycle) {
                        lifecycle.markFinished()
                        break
                    }

                    previousSpeed = speed

                    try? await Task.sleep(nanoseconds: baseTick)
                }

                self.clearStreetCarSnapshot(for: object.id)
                self.stopAndDetach(audio)
                self.activeTrafficPlayers.removeValue(forKey: object.id)
                self.activeTrafficTasks.removeValue(forKey: object.id)
                self.activeTrafficRoutes.removeValue(forKey: object.id)
                self.activeTrafficCues.removeValue(forKey: object.id)
                self.activeTrafficSpeedBands.removeValue(forKey: object.id)
                self.activeCourtyardParkingIDs.remove(object.id)
                self.forcedDepartureIDs.remove(object.id)
            }

            activeTrafficTasks[object.id] = motionTask
        } catch {
        }
    }
}
