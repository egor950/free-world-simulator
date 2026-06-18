import Foundation

extension StreetTrafficCoordinator {
    var trafficProfiles: [TrafficProfile] {
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

    func ensureDriveableCourtyardCar() {
        let alreadyHasDriveable = activeStreetCarSnapshots.values.contains {
            $0.isParked && $0.vehicleKind != .roadster
        }
        guard !alreadyHasDriveable else { return }
        guard activeDebugScenario == nil else { return }

        let preferredProfiles = trafficProfiles.filter {
            vehicleKind(for: $0.cue) != .roadster
        }
        guard let profile = preferredProfiles.randomElement() else { return }
        let buffer = trafficBufferCache[profile.cue] ?? loadPCMBuffer(for: profile.cue)
        guard let buffer else { return }
        trafficBufferCache[profile.cue] = buffer

        let plan = makeCourtyardAccessPlan(
            entrySide: .left,
            exitSide: .right,
            parkingPoint: OutdoorWorldPoint(x: -4.5, z: 3.4)
        )

        let object = TrafficObject(
            id: UUID(),
            profile: profile,
            speedBand: .slow,
            directionLeftToRight: true,
            routeStyle: .courtyardParking,
            courtyardAccessPlan: plan,
            startPhase: .parked,
            baseVolume: min(1.0, profile.cue.defaultVolume * profile.volumeBoost * 1.25),
            toneOffset: 0,
            sampleRate: buffer.format.sampleRate,
            startX: plan.parkingPoint.x,
            startZ: plan.parkingPoint.z,
            endX: plan.parkingPoint.x,
            finalExitX: plan.streetDeparturePoint.x,
            roadZ: courtyardMainStreetLaneZ,
            nearZ: plan.parkingPoint.z,
            entrySpeed: 0,
            cruiseSpeed: 2.8,
            maxSpeed: 3.6,
            acceleration: 2.8,
            brakeDeceleration: 3.4,
            rollingDeceleration: 0.32,
            dragFactor: 0.028,
            brakeTargetSpeed: 0.34,
            brakeCenterX: plan.parkingPoint.x,
            brakeHalfWidth: max(6.0, abs(plan.parkingPoint.x - plan.courtyardEntryPoint.x)),
            parkHoldDuration: 600
        )

        parkingSpawnDirector.markParkingRouteStarted(at: Date())
        startTrafficObject(object, buffer: buffer)
    }

    func spawnTrafficPass() {
        guard activeDebugScenario == nil else { return }

        let profiles = trafficProfiles
        let now = Date()
        let routeStyle = routeStyleForNextSpawn(now: now)
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
            lastCourtyardParkingCue = object.profile.cue
            parkingSpawnDirector.markParkingRouteStarted(at: now)
        }
        startTrafficObject(object, buffer: buffer)
    }

    func makeDebugTrafficObject(
        for scenario: DebugScenario,
        profile: TrafficProfile,
        sampleRate: Double
    ) -> TrafficObject {
        let accessPlan = debugCourtyardAccessPlan(for: scenario)
        let startPoint = debugStartPoint(for: scenario, plan: accessPlan)
        let startPhase = debugStartPhase(for: scenario)
        let parkHoldDuration = debugParkHoldDuration(for: scenario)
        let directionLeftToRight = accessPlan.entrySide == .left

        return TrafficObject(
            id: UUID(),
            profile: profile,
            speedBand: .slow,
            directionLeftToRight: directionLeftToRight,
            routeStyle: .courtyardParking,
            courtyardAccessPlan: accessPlan,
            startPhase: startPhase,
            baseVolume: min(1.0, profile.cue.defaultVolume * profile.volumeBoost * 1.4),
            toneOffset: 0,
            sampleRate: sampleRate,
            startX: startPoint.x,
            startZ: startPoint.z,
            endX: accessPlan.parkingPoint.x,
            finalExitX: accessPlan.streetDeparturePoint.x,
            roadZ: courtyardMainStreetLaneZ,
            nearZ: accessPlan.parkingPoint.z,
            entrySpeed: 1.6,
            cruiseSpeed: 2.8,
            maxSpeed: 3.6,
            acceleration: 2.8,
            brakeDeceleration: 3.4,
            rollingDeceleration: 0.32,
            dragFactor: 0.028,
            brakeTargetSpeed: 0.34,
            brakeCenterX: accessPlan.parkingPoint.x,
            brakeHalfWidth: max(6.0, abs(accessPlan.parkingPoint.x - accessPlan.courtyardEntryPoint.x)),
            parkHoldDuration: parkHoldDuration
        )
    }

    func makeTrafficObject(
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
        if routeStyle == .courtyardParking, !activeCourtyardParkingIDs.isEmpty {
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
        let courtyardAccessPlan = normalizedRouteStyle == .courtyardParking
            ? makeCourtyardAccessPlan(directionLeftToRight: directionLeftToRight)
            : nil

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
            startX = directionLeftToRight ? -46 : 46
            endX = courtyardAccessPlan?.parkingPoint.x ?? (directionLeftToRight ? 8 : -8)
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
            roadZ = max(20, roadDepth(for: distance) * 0.88)
            nearZ = max(16, roadZ - 4.0)
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
            roadZ = courtyardMainStreetLaneZ
            nearZ = courtyardAccessPlan?.parkingPoint.z ?? 3.8
            finalExitX = courtyardAccessPlan?.streetDeparturePoint.x ?? (directionLeftToRight ? 52 : -52)
            maxSpeed = Float.random(in: profile.parkingSpeedRange) * speedRate
            cruiseSpeed = maxSpeed * 0.9
            entrySpeed = max(0.8, cruiseSpeed * 0.22)
            acceleration = (2.4 + speedRate * 1.8) * profile.accelerationScale
            brakeDeceleration = (3.2 + speedRate * 1.8) * profile.brakeScale
            rollingDeceleration = 0.34
            dragFactor = 0.028
            brakeTargetSpeed = max(0.3, cruiseSpeed * 0.18)
            brakeCenterX = courtyardAccessPlan?.parkingPoint.x ?? (directionLeftToRight ? 6.5 : -6.5)
            brakeHalfWidth = max(6.0, abs((courtyardAccessPlan?.parkingPoint.x ?? 0) - (courtyardAccessPlan?.courtyardEntryPoint.x ?? 0)))
            parkHoldDuration = Float.random(in: 16.0...24.0)
        }

        return TrafficObject(
            id: UUID(),
            profile: profile,
            speedBand: speedBand,
            directionLeftToRight: directionLeftToRight,
            routeStyle: normalizedRouteStyle,
            courtyardAccessPlan: courtyardAccessPlan,
            startPhase: normalizedRouteStyle == .courtyardParking ? .streetApproach : .passing,
            baseVolume: baseVolume,
            toneOffset: toneOffset,
            sampleRate: sampleRate,
            startX: startX,
            startZ: roadZ,
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
}
