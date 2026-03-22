@preconcurrency import AVFoundation
import Foundation

@MainActor
final class StreetTrafficCoordinator {
    private static let desiredMinimumTrafficCount = 2
    private static let maximumTrafficCount = 3
    enum DebugScenario: String, CaseIterable {
        case parkedCar = "street_parked_car"
        case approachingCar = "street_approaching_car"
        case departingCar = "street_departing_car"
    }

    struct StreetCarSnapshot: Equatable {
        let id: UUID
        let title: String
        let shortPrompt: String
        let fullDescription: String
        let position: GridPosition
        let isParked: Bool
        let isInspectable: Bool
    }

    struct TrafficProfile {
        let cue: AudioCueID
        let cruiseRateRange: ClosedRange<Float>
        let brakeDepthRange: ClosedRange<Float>
        let volumeBoost: Float
        let roadPassSpeedRange: ClosedRange<Float>
        let slowRollSpeedRange: ClosedRange<Float>
        let parkingSpeedRange: ClosedRange<Float>
        let accelerationScale: Float
        let brakeScale: Float
        let idleEngineHz: Double
        let maxEngineHz: Double
        let gearShiftEngineHz: Double
        let gearCount: Int
    }

    enum TrafficRouteStyle {
        case roadPass
        case courtyardParking
        case slowRollBy
    }

    private enum TrafficDistanceBand: CaseIterable {
        case close
        case medium
        case far

        var volumeMultiplier: Float {
            switch self {
            case .close:
                return 1.35
            case .medium:
                return 1.0
            case .far:
                return 0.78
            }
        }
    }

    enum TrafficSpeedBand: CaseIterable {
        case slow
        case normal
        case fast
    }

    struct TrafficObject {
        let id: UUID
        let profile: TrafficProfile
        let speedBand: TrafficSpeedBand
        let directionLeftToRight: Bool
        let routeStyle: TrafficRouteStyle
        let baseVolume: Float
        let toneOffset: Float
        let sampleRate: Double
        let startX: Float
        let endX: Float
        let finalExitX: Float
        let roadZ: Float
        let nearZ: Float
        let entrySpeed: Float
        let cruiseSpeed: Float
        let maxSpeed: Float
        let acceleration: Float
        let brakeDeceleration: Float
        let rollingDeceleration: Float
        let dragFactor: Float
        let brakeTargetSpeed: Float
        let brakeCenterX: Float
        let brakeHalfWidth: Float
        let parkHoldDuration: Float
    }

    private struct TrafficEngineTuning {
        let idleHz: Double
        let topHz: Double
        let shiftHz: Double
        let gears: Int
    }

    private struct TrafficAudioUnit {
        let player: AVAudioPlayerNode
        let brakePlayer: AVAudioPlayerNode?
        let varispeed: AVAudioUnitVarispeed
        let eq: AVAudioUnitEQ
        let panner: AVAudioMixerNode
    }

    private let effectEngine: AVAudioEngine
    private let resourceURLProvider: (AudioCueID) -> URL?

    var onStreetCarsChanged: (([StreetCarSnapshot]) -> Void)?
    var onStreetCarParked: ((StreetCarSnapshot) -> Void)?

    private var activeTrafficPlayers: [UUID: TrafficAudioUnit] = [:]
    private var activeTrafficTasks: [UUID: Task<Void, Never>] = [:]
    var activeTrafficRoutes: [UUID: TrafficRouteStyle] = [:]
    var activeTrafficCues: [UUID: AudioCueID] = [:]
    private var activeTrafficSpeedBands: [UUID: TrafficSpeedBand] = [:]
    private var trafficBufferCache: [AudioCueID: AVAudioPCMBuffer] = [:]
    private var brakeBuffer: AVAudioPCMBuffer?
    private var trafficLoopTask: Task<Void, Never>?
    private var isEnabled = false
    var lastCourtyardParkingStartedAt: Date = .distantPast
    var lastCourtyardParkingCue: AudioCueID?
    private var listenerStreetPosition = GridPosition(x: 7, y: 14)
    private var forcedDepartureIDs: Set<UUID> = []
    private var activeDebugScenario: DebugScenario?
    private var activeStreetCarSnapshots: [UUID: StreetCarSnapshot] = [:] {
        didSet {
            guard activeStreetCarSnapshots != oldValue else { return }
            let snapshots = activeStreetCarSnapshots.values.sorted { lhs, rhs in
                if lhs.position.y == rhs.position.y {
                    return lhs.position.x < rhs.position.x
                }
                return lhs.position.y < rhs.position.y
            }
            onStreetCarsChanged?(snapshots)
        }
    }

    init(
        effectEngine: AVAudioEngine,
        resourceURLProvider: @escaping (AudioCueID) -> URL?
    ) {
        self.effectEngine = effectEngine
        self.resourceURLProvider = resourceURLProvider
    }

    private var trafficProfiles: [TrafficProfile] {
        [
            TrafficProfile(
                cue: .trafficEngineLight,
                cruiseRateRange: 0.88...1.12,
                brakeDepthRange: 0.64...0.86,
                volumeBoost: 0.92,
                roadPassSpeedRange: 12...18,
                slowRollSpeedRange: 7.5...10.5,
                parkingSpeedRange: 4.0...6.0,
                accelerationScale: 0.88,
                brakeScale: 0.92,
                idleEngineHz: 12_200,
                maxEngineHz: 36_000,
                gearShiftEngineHz: 27_200,
                gearCount: 5
            ),
            TrafficProfile(
                cue: .trafficEngineSedan,
                cruiseRateRange: 0.8...1.02,
                brakeDepthRange: 0.62...0.84,
                volumeBoost: 0.96,
                roadPassSpeedRange: 11...17,
                slowRollSpeedRange: 7.0...10.0,
                parkingSpeedRange: 4.0...5.8,
                accelerationScale: 0.95,
                brakeScale: 0.96,
                idleEngineHz: 11_025,
                maxEngineHz: 31_000,
                gearShiftEngineHz: 22_500,
                gearCount: 5
            ),
            TrafficProfile(
                cue: .trafficEngineSport,
                cruiseRateRange: 1.0...1.24,
                brakeDepthRange: 0.76...0.98,
                volumeBoost: 0.9,
                roadPassSpeedRange: 16...24,
                slowRollSpeedRange: 9.5...14.5,
                parkingSpeedRange: 5.0...7.6,
                accelerationScale: 1.18,
                brakeScale: 1.05,
                idleEngineHz: 11_025,
                maxEngineHz: 45_500,
                gearShiftEngineHz: 32_900,
                gearCount: 6
            ),
            TrafficProfile(
                cue: .trafficEngineCoupe,
                cruiseRateRange: 0.92...1.18,
                brakeDepthRange: 0.7...0.92,
                volumeBoost: 0.93,
                roadPassSpeedRange: 14...20,
                slowRollSpeedRange: 8.5...12.0,
                parkingSpeedRange: 4.8...7.0,
                accelerationScale: 1.04,
                brakeScale: 1.0,
                idleEngineHz: 11_025,
                maxEngineHz: 60_000,
                gearShiftEngineHz: 43_000,
                gearCount: 6
            ),
            TrafficProfile(
                cue: .trafficEngineRoadster,
                cruiseRateRange: 1.04...1.3,
                brakeDepthRange: 0.74...0.96,
                volumeBoost: 0.91,
                roadPassSpeedRange: 15...22,
                slowRollSpeedRange: 9.0...13.5,
                parkingSpeedRange: 5.0...7.3,
                accelerationScale: 1.12,
                brakeScale: 1.02,
                idleEngineHz: 11_025,
                maxEngineHz: 62_000,
                gearShiftEngineHz: 45_000,
                gearCount: 6
            )
        ]
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled

        if enabled {
            if lastCourtyardParkingStartedAt == .distantPast {
                lastCourtyardParkingStartedAt = Date()
            }
            if let scenario = activeDebugScenario {
                if activeTrafficPlayers.isEmpty {
                    runDebugScenarioInternal(scenario)
                }
            } else {
                startLoop()
            }
        } else {
            stopLoop()
        }
    }

    func setListenerStreetPosition(_ position: GridPosition) {
        listenerStreetPosition = position
    }

    func triggerDeparture(for carID: UUID) {
        forcedDepartureIDs.insert(carID)
    }

    func runDebugScenario(_ scenario: DebugScenario) {
        activeDebugScenario = scenario
        isEnabled = true
        stopLoop()
        runDebugScenarioInternal(scenario)
    }

    func clearDebugScenario() {
        activeDebugScenario = nil
        stopLoop()
        if isEnabled {
            startLoop()
        }
    }

    func debugSnapshotPayload() -> [[String: Any]] {
        activeStreetCarSnapshots.values.sorted { lhs, rhs in
            if lhs.position.y == rhs.position.y {
                return lhs.position.x < rhs.position.x
            }
            return lhs.position.y < rhs.position.y
        }.map { snapshot in
            [
                "id": snapshot.id.uuidString,
                "title": snapshot.title,
                "shortPrompt": snapshot.shortPrompt,
                "x": snapshot.position.x,
                "y": snapshot.position.y,
                "isParked": snapshot.isParked,
                "isInspectable": snapshot.isInspectable
            ]
        }
    }

    private func startLoop() {
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

    private func stopLoop() {
        trafficLoopTask?.cancel()
        trafficLoopTask = nil
        activeStreetCarSnapshots = [:]
        forcedDepartureIDs.removeAll()
        lastCourtyardParkingStartedAt = .distantPast
        lastCourtyardParkingCue = nil

        for task in activeTrafficTasks.values {
            task.cancel()
        }
        activeTrafficTasks.removeAll()
        activeTrafficRoutes.removeAll()
        activeTrafficCues.removeAll()
        activeTrafficSpeedBands.removeAll()

        for audio in activeTrafficPlayers.values {
            stopAndDetach(audio)
        }
        activeTrafficPlayers.removeAll()
    }

    private func cleanupFinishedTraffic() {
        let finishedIDs = activeTrafficPlayers.compactMap { id, audio in
            audio.player.isPlaying ? nil : id
        }

        for id in finishedIDs {
            if let audio = activeTrafficPlayers.removeValue(forKey: id) {
                activeTrafficRoutes.removeValue(forKey: id)
                activeTrafficCues.removeValue(forKey: id)
                activeTrafficSpeedBands.removeValue(forKey: id)
                clearStreetCarSnapshot(for: id)
                stopAndDetach(audio)
            }
        }
    }

    private func runDebugScenarioInternal(_ scenario: DebugScenario) {
        let profile = trafficProfiles.first(where: { $0.cue == .trafficEngineLight }) ?? trafficProfiles[0]
        let buffer = trafficBufferCache[profile.cue] ?? loadPCMBuffer(for: profile.cue)
        guard let buffer else { return }
        trafficBufferCache[profile.cue] = buffer

        let object = makeDebugTrafficObject(for: scenario, profile: profile, sampleRate: buffer.format.sampleRate)
        lastCourtyardParkingStartedAt = Date()
        startTrafficObject(object, buffer: buffer)
    }

    private func spawnTrafficPass() {
        guard activeDebugScenario == nil else { return }

        let profiles = trafficProfiles
        let routeStyle = routeStyleForNextSpawn()
        let profile = selectProfile(for: routeStyle, profiles: profiles)
        let buffer = trafficBufferCache[profile.cue] ?? loadPCMBuffer(for: profile.cue)
        guard let buffer else { return }
        trafficBufferCache[profile.cue] = buffer

        let object = makeTrafficObject(
            for: profile,
            sampleRate: buffer.format.sampleRate,
            routeStyle: routeStyle
        )
        if object.routeStyle == .courtyardParking {
            lastCourtyardParkingStartedAt = Date()
            lastCourtyardParkingCue = object.profile.cue
        }
        startTrafficObject(object, buffer: buffer)
    }

    private func startTrafficObject(_ object: TrafficObject, buffer: AVAudioPCMBuffer) {
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

            let motionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                guard let audio = self.activeTrafficPlayers[object.id] else { return }

                let dt: Float = 0.08
                var x = object.startX
                var z = object.roadZ
                var speed = object.entrySpeed
                var previousSpeed = speed
                var elapsed: Float = 0
                var parkedElapsed: Float = 0
                var departureElapsed: Float = 0
                var isParked = false
                var didCompleteParkingStop = false
                var currentRate = clampRate(tuning.idleHz / max(1, object.sampleRate))
                var previousGear = 1
                var shiftPulseUntil: Float = 0

                while true {
                    guard !Task.isCancelled, audio.player.isPlaying else { break }

                    elapsed += dt
                    if isParked {
                        parkedElapsed += dt
                    }

                    let targetSpeed = desiredSpeed(
                        for: object,
                        x: x,
                        z: z,
                        isParked: isParked,
                        parkedElapsed: parkedElapsed,
                        didCompleteParkingStop: didCompleteParkingStop,
                        departureElapsed: departureElapsed
                    )
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

                    if !isParked {
                        let direction: Float = object.directionLeftToRight ? 1 : -1
                        x += direction * speed * dt
                    }

                    z = trafficZ(for: object, x: x, isParked: isParked)
                    audio.panner.pan = self.trafficPan(for: object, x: x, z: z)
                    audio.panner.outputVolume = self.trafficVolume(for: object, x: x, z: z, speed: speed, isParked: isParked)
                    audio.brakePlayer?.volume = self.trafficBrakeSoundVolume(
                        for: object,
                        speed: speed,
                        previousSpeed: previousSpeed,
                        deltaTime: dt,
                        isParked: isParked,
                        didCompleteParkingStop: didCompleteParkingStop
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

                    if object.routeStyle == .courtyardParking {
                        if isParked, self.forcedDepartureIDs.contains(object.id) {
                            isParked = false
                            parkedElapsed = 0
                            departureElapsed = 0
                            didCompleteParkingStop = true
                            self.forcedDepartureIDs.remove(object.id)
                        }

                        let reachedParkingSpot = self.hasReachedParkingStop(
                            for: object,
                            x: x,
                            speed: speed,
                            previousSpeed: previousSpeed,
                            elapsed: elapsed
                        )
                        if reachedParkingSpot, !isParked, !didCompleteParkingStop {
                            speed = 0
                            previousSpeed = 0
                            isParked = true
                            parkedElapsed = 0
                            self.updateStreetCarSnapshot(for: object, x: x, z: z, isParked: true, isLeaving: false)
                            if let snapshot = self.activeStreetCarSnapshots[object.id] {
                                self.onStreetCarParked?(snapshot)
                            }
                        }
                        if isParked && parkedElapsed >= object.parkHoldDuration {
                            isParked = false
                            parkedElapsed = 0
                            departureElapsed = 0
                            didCompleteParkingStop = true
                        }
                        if didCompleteParkingStop && !isParked {
                            departureElapsed += dt
                            self.updateStreetCarSnapshot(for: object, x: x, z: z, isParked: false, isLeaving: true)
                        } else if isParked {
                            self.updateStreetCarSnapshot(for: object, x: x, z: z, isParked: true, isLeaving: false)
                        } else if !didCompleteParkingStop {
                            self.updateStreetCarSnapshot(for: object, x: x, z: z, isParked: false, isLeaving: false)
                        }

                        let departureExitX: Float = object.directionLeftToRight ? 36 : -36
                        let passedDepartureExit = object.directionLeftToRight ? x >= departureExitX : x <= departureExitX
                        if didCompleteParkingStop && passedDepartureExit {
                            break
                        }
                    } else {
                        let exitX = object.finalExitX
                        let passedRoadBounds = object.directionLeftToRight ? x >= exitX : x <= exitX
                        if passedRoadBounds {
                            break
                        }
                    }

                    previousSpeed = speed

                    try? await Task.sleep(nanoseconds: UInt64(dt * 1_000_000_000))
                }

                self.clearStreetCarSnapshot(for: object.id)
                self.stopAndDetach(audio)
                self.activeTrafficPlayers.removeValue(forKey: object.id)
                self.activeTrafficTasks.removeValue(forKey: object.id)
                self.activeTrafficRoutes.removeValue(forKey: object.id)
                self.activeTrafficCues.removeValue(forKey: object.id)
                self.activeTrafficSpeedBands.removeValue(forKey: object.id)
                self.forcedDepartureIDs.remove(object.id)
            }

            activeTrafficTasks[object.id] = motionTask
        } catch {
        }
    }

    private func makeDebugTrafficObject(
        for scenario: DebugScenario,
        profile: TrafficProfile,
        sampleRate: Double
    ) -> TrafficObject {
        let startX: Float
        let parkHoldDuration: Float

        switch scenario {
        case .parkedCar:
            startX = -18
            parkHoldDuration = 600
        case .approachingCar:
            startX = -24
            parkHoldDuration = 600
        case .departingCar:
            startX = -10.5
            parkHoldDuration = 0.25
        }

        return TrafficObject(
            id: UUID(),
            profile: profile,
            speedBand: .slow,
            directionLeftToRight: true,
            routeStyle: .courtyardParking,
            baseVolume: min(1.0, profile.cue.defaultVolume * profile.volumeBoost * 1.4),
            toneOffset: 0,
            sampleRate: sampleRate,
            startX: startX,
            endX: -8,
            finalExitX: 36,
            roadZ: 6.8,
            nearZ: 3.8,
            entrySpeed: 1.1,
            cruiseSpeed: 2.3,
            maxSpeed: 3.0,
            acceleration: 1.35,
            brakeDeceleration: 2.6,
            rollingDeceleration: 0.96,
            dragFactor: 0.036,
            brakeTargetSpeed: 0.34,
            brakeCenterX: -7.2,
            brakeHalfWidth: 5.8,
            parkHoldDuration: parkHoldDuration
        )
    }

    private func makeTrafficObject(
        for profile: TrafficProfile,
        sampleRate: Double,
        routeStyle: TrafficRouteStyle
    ) -> TrafficObject {
        let directionLeftToRight = directionForSpawn(routeStyle: routeStyle)
        let distance = TrafficDistanceBand.allCases.randomElement() ?? .medium
        let usedSpeedBands = Set(activeTrafficSpeedBands.values)
        let availableSpeedBands = TrafficSpeedBand.allCases.filter { !usedSpeedBands.contains($0) }
        let speedBand = (availableSpeedBands.isEmpty ? TrafficSpeedBand.allCases : availableSpeedBands).randomElement() ?? .normal

        let normalizedRouteStyle: TrafficRouteStyle
        if routeStyle == .courtyardParking, activeTrafficRoutes.values.contains(.courtyardParking) {
            normalizedRouteStyle = .slowRollBy
        } else {
            normalizedRouteStyle = routeStyle
        }

        let speedRate = adjustedSpeedRate(
            base: Float.random(in: profile.cruiseRateRange),
            speedBand: speedBand,
            routeStyle: normalizedRouteStyle
        )
        let baseVolume = min(1.0, profile.cue.defaultVolume * distance.volumeMultiplier * profile.volumeBoost * 1.85)

        let startX: Float
        let endX: Float
        switch normalizedRouteStyle {
        case .roadPass:
            startX = directionLeftToRight ? -34 : 34
            endX = directionLeftToRight ? 34 : -34
        case .slowRollBy:
            startX = directionLeftToRight ? -26 : 26
            endX = directionLeftToRight ? 20 : -20
        case .courtyardParking:
            startX = -24
            endX = -8
        }

        let toneOffset = Float.random(in: -0.2...0.2)
        let roadZ: Float
        let nearZ: Float
        let finalExitX: Float
        let maxSpeed: Float
        let cruiseSpeed: Float
        let entrySpeed: Float
        let acceleration: Float
        let brakeDeceleration: Float
        let rollingDeceleration: Float
        let dragFactor: Float
        let brakeTargetSpeed: Float
        let brakeCenterX: Float
        let brakeHalfWidth: Float
        let parkHoldDuration: Float

        switch normalizedRouteStyle {
        case .roadPass:
            roadZ = roadDepth(for: distance)
            nearZ = roadZ
            finalExitX = directionLeftToRight ? endX + 8 : endX - 8
            maxSpeed = Float.random(in: profile.roadPassSpeedRange) * speedRate
            cruiseSpeed = maxSpeed * 0.94
            entrySpeed = max(0.8, cruiseSpeed * 0.06)
            acceleration = (2.0 + speedRate * 2.0) * profile.accelerationScale
            brakeDeceleration = (4.1 + speedRate * 3.1) * profile.brakeScale
            rollingDeceleration = 0.55
            dragFactor = 0.026
            brakeTargetSpeed = cruiseSpeed * Float.random(in: 0.35...0.88)
            brakeCenterX = Float.random(in: -8...8)
            brakeHalfWidth = Float.random(in: 3.5...7.0)
            parkHoldDuration = 0
        case .slowRollBy:
            roadZ = max(7, roadDepth(for: distance) * 0.56)
            nearZ = max(5.6, roadZ - 2.6)
            finalExitX = directionLeftToRight ? endX + 8 : endX - 8
            maxSpeed = Float.random(in: profile.slowRollSpeedRange) * speedRate
            cruiseSpeed = maxSpeed * 0.8
            entrySpeed = max(0.7, cruiseSpeed * 0.08)
            acceleration = (1.4 + speedRate * 1.4) * profile.accelerationScale
            brakeDeceleration = (2.8 + speedRate * 1.8) * profile.brakeScale
            rollingDeceleration = 0.72
            dragFactor = 0.032
            brakeTargetSpeed = cruiseSpeed * Float.random(in: 0.24...0.52)
            brakeCenterX = directionLeftToRight ? 8.5 : -8.5
            brakeHalfWidth = Float.random(in: 6.0...10.0)
            parkHoldDuration = 0
        case .courtyardParking:
            roadZ = max(6.6, roadDepth(for: distance) * 0.48)
            nearZ = 3.8
            finalExitX = directionLeftToRight ? 36 : -36
            maxSpeed = Float.random(in: profile.parkingSpeedRange) * speedRate
            cruiseSpeed = maxSpeed * 0.76
            entrySpeed = max(0.5, cruiseSpeed * 0.06)
            acceleration = (1.0 + speedRate * 0.9) * profile.accelerationScale
            brakeDeceleration = (2.5 + speedRate * 1.4) * profile.brakeScale
            rollingDeceleration = 0.96
            dragFactor = 0.036
            brakeTargetSpeed = max(0.3, cruiseSpeed * 0.18)
            brakeCenterX = directionLeftToRight ? 6.5 : -6.5
            brakeHalfWidth = Float.random(in: 8.0...12.0)
            parkHoldDuration = Float.random(in: 16.0...24.0)
        }

        return TrafficObject(
            id: UUID(),
            profile: profile,
            speedBand: speedBand,
            directionLeftToRight: directionLeftToRight,
            routeStyle: normalizedRouteStyle,
            baseVolume: baseVolume,
            toneOffset: toneOffset,
            sampleRate: sampleRate,
            startX: startX,
            endX: endX,
            finalExitX: finalExitX,
            roadZ: roadZ,
            nearZ: nearZ,
            entrySpeed: entrySpeed,
            cruiseSpeed: cruiseSpeed,
            maxSpeed: maxSpeed,
            acceleration: acceleration,
            brakeDeceleration: brakeDeceleration,
            rollingDeceleration: rollingDeceleration,
            dragFactor: dragFactor,
            brakeTargetSpeed: brakeTargetSpeed,
            brakeCenterX: brakeCenterX,
            brakeHalfWidth: brakeHalfWidth,
            parkHoldDuration: parkHoldDuration
        )
    }

    private func makeTuning(for object: TrafficObject) -> TrafficEngineTuning {
        let idle = max(500, object.profile.idleEngineHz)
        let top = max(idle + 500, object.profile.maxEngineHz)
        let shift = min(top - 100, max(idle + 100, object.profile.gearShiftEngineHz))
        let gears = max(2, min(10, object.profile.gearCount))
        return TrafficEngineTuning(idleHz: idle, topHz: top, shiftHz: shift, gears: gears)
    }

    private func makeAudioUnit(for object: TrafficObject, buffer: AVAudioPCMBuffer) throws -> TrafficAudioUnit {
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

    private func configureEQ(_ eq: AVAudioUnitEQ, object: TrafficObject) {
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

    private func stopAndDetach(_ audio: TrafficAudioUnit) {
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

    private func makeBrakePlayer() -> AVAudioPlayerNode? {
        if brakeBuffer == nil {
            brakeBuffer = loadPCMBuffer(for: .trafficBrakeSoft)
        }
        guard brakeBuffer != nil else { return nil }
        return AVAudioPlayerNode()
    }

    private func loadPCMBuffer(for cue: AudioCueID) -> AVAudioPCMBuffer? {
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

    private func adjustedSpeedRate(base: Float, speedBand: TrafficSpeedBand, routeStyle: TrafficRouteStyle) -> Float {
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

    private func advanceSpeed(
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

    private func trafficBrakeSoundVolume(
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

    private func engineRate(
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

    private func currentGear(speedNorm: Float, gears: Int) -> Int {
        let clamped = min(1.0, max(0.0, Double(speedNorm)))
        return min(gears, max(1, Int(clamped * Double(gears)) + 1))
    }

    private func smoothRate(previousRate: Float, targetRate: Float, routeStyle: TrafficRouteStyle) -> Float {
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

    private func clampRate(_ raw: Double) -> Float {
        Float(min(3.2, max(0.45, raw)))
    }

    private func trafficZ(for object: TrafficObject, x: Float, isParked: Bool) -> Float {
        guard object.routeStyle == .courtyardParking else { return object.roadZ }
        if isParked { return object.nearZ }
        let approachMix = 1 - min(1.0, abs(x - object.endX) / 12.0)
        return trafficInterpolate(from: object.roadZ, to: object.nearZ, progress: max(0, approachMix))
    }

    private func trafficPan(for object: TrafficObject, x: Float, z: Float) -> Float {
        let listenerX = streetWorldX(for: listenerStreetPosition)
        let relativeX = x - listenerX
        let panBase = max(-1.0, min(1.0, relativeX / 14.0))
        let sideBias: Float
        switch object.routeStyle {
        case .roadPass:
            sideBias = 0
        case .slowRollBy:
            sideBias = object.directionLeftToRight ? -0.04 : 0.04
        case .courtyardParking:
            sideBias = object.directionLeftToRight ? -0.08 : 0.08
        }
        return max(-0.96, min(0.96, panBase + sideBias))
    }

    private func trafficVolume(for object: TrafficObject, x: Float, z: Float, speed: Float, isParked: Bool) -> Float {
        let listenerX = streetWorldX(for: listenerStreetPosition)
        let listenerZ = streetWorldZ(for: listenerStreetPosition)
        let dx = x - listenerX
        let dz = z - listenerZ
        let distance = sqrt((dx * dx) + (dz * dz))
        let audibleRadius: Float = object.routeStyle == .courtyardParking ? 30 : 42
        let distanceFade = max(0, 1 - (distance / audibleRadius))
        let distanceMix = pow(distanceFade, 1.8)
        let motionBoost = isParked ? 0.8 : min(1.0, 0.48 + (speed / max(0.1, object.maxSpeed)) * 0.94)
        let travelDistance = max(1, abs(object.finalExitX - object.startX))
        let traveled = abs(x - object.startX)
        let remaining = abs(object.finalExitX - x)
        let fadeIn = min(1.0, traveled / max(6, travelDistance * 0.18))
        let fadeOut = min(1.0, remaining / max(7, travelDistance * 0.16))
        let routeFade = isParked ? fadeIn : min(fadeIn, fadeOut)
        let routeBoost: Float
        switch object.routeStyle {
        case .roadPass:
            routeBoost = 1.0
        case .slowRollBy:
            routeBoost = 1.08
        case .courtyardParking:
            routeBoost = isParked ? 0.94 : 1.05
        }
        return min(1.0, object.baseVolume * motionBoost * routeBoost * distanceMix * routeFade)
    }

    private func roadDepth(for distance: TrafficDistanceBand) -> Float {
        switch distance {
        case .close:
            return 7
        case .medium:
            return 12
        case .far:
            return 18
        }
    }

    private func updateStreetCarSnapshot(for object: TrafficObject, x: Float, z: Float, isParked: Bool, isLeaving: Bool) {
        let title = streetCarTitle(for: object.profile.cue)
        let hint = streetCarRelativeHint(x: x, z: z)
        let snapshotPosition = streetGridPosition(for: object, x: x, z: z, isParked: isParked, isLeaving: isLeaving)
        let playerDistance = abs(snapshotPosition.x - listenerStreetPosition.x) + abs(snapshotPosition.y - listenerStreetPosition.y)
        let isInspectable = isParked
        let shortPrompt: String
        let fullDescription: String

        if isParked && playerDistance <= 1 {
            shortPrompt = "Рядом \(title)."
            fullDescription = "Перед тобой \(title). \(streetCarAppearanceDescription(for: object.profile.cue)) Корпус еще теплый, рядом чувствуются двери, стекла и линия капота, а мотор хорошо слышен совсем близко."
        } else if isLeaving {
            shortPrompt = "\(hint) \(title). Мотор ожил, машина начинает уезжать."
            fullDescription = "Перед тобой \(title). \(streetCarAppearanceDescription(for: object.profile.cue)) Она уже тронулась, мотор набирает силу, и машина уходит со двора."
        } else if isParked {
            shortPrompt = "Слева во дворе \(title). Она стоит и тихо урчит на холостых."
            fullDescription = "Перед тобой \(title). \(streetCarAppearanceDescription(for: object.profile.cue)) Она припаркована слева во дворе, мотор мягко урчит, а если подойти ближе, хорошо чувствуются двери, стекла, капот и спокойные холостые обороты."
        } else if object.routeStyle == .courtyardParking {
            shortPrompt = "Слева \(title). Она заезжает во двор."
            fullDescription = "Перед тобой \(title). \(streetCarAppearanceDescription(for: object.profile.cue)) Она ещё едет и тормозит, докатываясь до парковочного места."
        } else {
            let directionText = object.directionLeftToRight ? "Она едет слева направо." : "Она едет справа налево."
            shortPrompt = "\(hint) \(title). \(directionText)"
            fullDescription = "Перед тобой \(title). \(streetCarAppearanceDescription(for: object.profile.cue)) \(directionText) Слышно, как двигатель сначала мягко набирает ход, потом ровно тянет по улице."
        }

        activeStreetCarSnapshots[object.id] = StreetCarSnapshot(
            id: object.id,
            title: title,
            shortPrompt: shortPrompt,
            fullDescription: fullDescription,
            position: snapshotPosition,
            isParked: isParked,
            isInspectable: isInspectable
        )
    }

    private func clearStreetCarSnapshot(for id: UUID) {
        activeStreetCarSnapshots[id] = nil
    }

    private func streetGridPosition(
        for object: TrafficObject,
        x: Float,
        z: Float,
        isParked: Bool,
        isLeaving: Bool
    ) -> GridPosition {
        _ = object
        _ = isParked
        _ = isLeaving
        return streetGridPositionForWorldPoint(x: x, z: z)
    }

    private func streetGridPositionForWorldPoint(x: Float, z: Float) -> GridPosition {
        let gridX = Int(round(((x + 34) / 68) * 14))
        let gridY = Int(round(7 - (z / 2.5)))
        return GridPosition(
            x: min(14, max(0, gridX)),
            y: min(14, max(0, gridY))
        )
    }

    private func streetCarAppearanceDescription(for cue: AudioCueID) -> String {
        switch cue {
        case .trafficEngineLight:
            return "Это небольшая легкая машина, аккуратная и узкая, с короткими дверями, тонкими боковыми стеклами и мягким ровным мотором."
        case .trafficEngineSedan:
            return "Это обычный седан, с плотным кузовом, обычными дверями, широкими стеклами и спокойным тяжелым урчанием мотора под капотом."
        case .trafficEngineSport:
            return "Это спортивная машина, низкая и резкая по звуку, с тяжелыми дверями, вытянутым капотом и мотором, который будто готов к быстрому рывку."
        case .trafficEngineCoupe:
            return "Это купе, собранное и упругое, с длинной боковой дверью, гладкой линией стекла и бодрым мотором без лишнего визга."
        case .trafficEngineRoadster:
            return "Это родстер, легкий и звонкий, с низкой посадкой, коротким ветровым стеклом и живым мотором с резким характером."
        default:
            return "Это машина с хорошо слышным мотором, дверями по бокам, стеклами и теплым капотом спереди."
        }
    }

    private func streetWorldX(for position: GridPosition) -> Float {
        (Float(position.x) / 14.0) * 68.0 - 34.0
    }

    private func streetWorldZ(for position: GridPosition) -> Float {
        Float(7 - position.y) * 2.5
    }

    private func streetCarTitle(for cue: AudioCueID) -> String {
        switch cue {
        case .trafficEngineLight:
            return "легкая машина"
        case .trafficEngineSedan:
            return "седан"
        case .trafficEngineSport:
            return "спортивная машина"
        case .trafficEngineCoupe:
            return "купе"
        case .trafficEngineRoadster:
            return "родстер"
        default:
            return "машина"
        }
    }

    private func streetCarRelativeHint(x: Float, z: Float) -> String {
        let sideText: String
        if x <= -6 {
            sideText = "Слева"
        } else if x >= 6 {
            sideText = "Справа"
        } else {
            sideText = "Прямо впереди"
        }

        if z <= 5 {
            return "\(sideText), совсем рядом"
        }
        if z <= 10 {
            return "\(sideText), недалеко"
        }
        return "\(sideText), дальше по улице"
    }

    private func trafficAudioPosition(x: Float, z: Float) -> AVAudio3DPoint {
        AVAudio3DPoint(x: x, y: 0, z: -z)
    }

    private func streetListenerWorldPosition(for position: GridPosition?) -> AVAudio3DPoint {
        guard let position else {
            return AVAudio3DPoint(x: 0, y: 0, z: 0)
        }

        let worldX = Float(position.x - 7) * 4.8
        let worldZ = Float(position.y - 7) * 4.8
        return AVAudio3DPoint(x: worldX, y: 0, z: worldZ)
    }
}

func trafficInterpolate(from start: Float, to end: Float, progress: Float) -> Float {
    start + ((end - start) * progress)
}
