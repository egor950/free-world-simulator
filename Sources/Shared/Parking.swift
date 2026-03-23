import Foundation

extension StreetTrafficCoordinator {
    static let baseParkingSpawnChance: Float = 0.22
    static let parkingChanceRampInterval: TimeInterval = 14
    static let guaranteedParkingInterval: TimeInterval = 22
    static let fallbackSlowRollChance = 24
    static let minimumParkingApproachTime: Float = 2.2
    static let maximumParkingApproachTime: Float = 12.0
    static let parkingStopSpeedThreshold: Float = 0.06
    static let parkingStopApproachDistance: Float = 4.2

    func routeStyleForNextSpawn() -> TrafficRouteStyle {
        if shouldSpawnParkingCar() {
            return .courtyardParking
        }

        let routeRoll = Int.random(in: 1...100)
        if routeRoll <= Self.fallbackSlowRollChance {
            return .slowRollBy
        }
        return .roadPass
    }

    func selectProfile(
        for routeStyle: TrafficRouteStyle,
        profiles: [TrafficProfile]
    ) -> TrafficProfile {
        let activeCues = Set(activeTrafficCues.values)
        let availableProfiles = profiles.filter { !activeCues.contains($0.cue) }
        let basePool = availableProfiles.isEmpty ? profiles : availableProfiles

        guard routeStyle == .courtyardParking else {
            return basePool.randomElement() ?? profiles[0]
        }

        let rotatedPool = basePool.filter { $0.cue != lastCourtyardParkingCue }
        return (rotatedPool.isEmpty ? basePool : rotatedPool).randomElement() ?? profiles[0]
    }

    func shouldSpawnParkingCar(now: Date = Date()) -> Bool {
        guard !activeTrafficRoutes.values.contains(.courtyardParking) else {
            return false
        }

        guard lastCourtyardParkingStartedAt != .distantPast else {
            return true
        }

        let elapsed = now.timeIntervalSince(lastCourtyardParkingStartedAt)
        if elapsed >= Self.guaranteedParkingInterval {
            return true
        }

        let rampProgress = max(0.0, min(1.0, elapsed / Self.parkingChanceRampInterval))
        let chance = Self.baseParkingSpawnChance + Float(rampProgress) * 0.44
        return Float.random(in: 0...1) < chance
    }

    func directionForSpawn(routeStyle: TrafficRouteStyle) -> Bool {
        Bool.random()
    }

    func hasReachedParkingStop(
        for object: TrafficObject,
        x: Float,
        speed: Float,
        previousSpeed: Float,
        elapsed: Float
    ) -> Bool {
        guard object.routeStyle == .courtyardParking else { return false }

        let closeEnoughToCourtyard = abs(x - object.endX) <= Self.parkingStopApproachDistance
        let slowEnough = speed <= max(Self.parkingStopSpeedThreshold, object.brakeTargetSpeed * 0.28)
        let settledEnough = previousSpeed <= max(0.16, object.brakeTargetSpeed * 0.95)
        return closeEnoughToCourtyard && slowEnough && settledEnough && elapsed >= Self.minimumParkingApproachTime
    }

    func desiredSpeed(
        for object: TrafficObject,
        x: Float,
        z: Float,
        isParked: Bool,
        parkedElapsed: Float,
        didCompleteParkingStop: Bool,
        departureElapsed: Float
    ) -> Float {
        if isParked {
            return parkedElapsed >= object.parkHoldDuration ? max(0.5, object.brakeTargetSpeed * 0.9) : max(0.22, object.brakeTargetSpeed * 0.32)
        }

        let distanceFromBrakeCenter = abs(x - object.brakeCenterX)
        let brakeMix = 1 - min(1.0, distanceFromBrakeCenter / max(0.01, object.brakeHalfWidth))
        let softBrakeSpeed = trafficInterpolate(from: object.cruiseSpeed, to: object.brakeTargetSpeed, progress: brakeMix)

        switch object.routeStyle {
        case .roadPass:
            return max(object.brakeTargetSpeed, softBrakeSpeed)
        case .slowRollBy:
            let finishMix = min(1.0, abs(x / max(1.0, object.endX)))
            let target = trafficInterpolate(from: softBrakeSpeed, to: object.brakeTargetSpeed, progress: finishMix * 0.45)
            return max(object.brakeTargetSpeed, target)
        case .courtyardParking:
            if didCompleteParkingStop {
                let departureMix = min(1.0, departureElapsed / 3.2)
                let departureTarget = max(object.maxSpeed * 0.72, object.cruiseSpeed * 0.84)
                return trafficInterpolate(
                    from: max(object.brakeTargetSpeed * 0.72, 0.42),
                    to: departureTarget,
                    progress: departureMix
                )
            }
            let nearGoalMix = 1 - min(1.0, abs(x - object.endX) / 7.0)
            let zMix = 1 - min(1.0, abs(z - object.nearZ) / max(1.0, object.roadZ - object.nearZ))
            let parkingMix = pow(max(nearGoalMix, zMix), 1.65)
            return trafficInterpolate(from: softBrakeSpeed, to: 0, progress: parkingMix)
        }
    }
}
