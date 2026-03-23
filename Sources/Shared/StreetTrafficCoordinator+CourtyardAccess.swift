import Foundation

extension StreetTrafficCoordinator {
    struct CourtyardAccessPlan {
        let entrySide: CourtyardHiddenSide
        let exitSide: CourtyardHiddenSide
        let streetEntryTurnPoint: OutdoorWorldPoint
        let courtyardEntryPoint: OutdoorWorldPoint
        let parkingPoint: OutdoorWorldPoint
        let courtyardExitPoint: OutdoorWorldPoint
        let streetExitPoint: OutdoorWorldPoint
        let streetDeparturePoint: OutdoorWorldPoint
    }

    enum CourtyardHiddenSide: CaseIterable {
        case left
        case right
    }

    struct OutdoorWorldPoint {
        var x: Float
        var z: Float
    }

    var courtyardMainStreetLaneZ: Float { 23.5 }
    var courtyardHiddenEntryZ: Float { 1.2 }
    var courtyardLeftEntryX: Float { -22.0 }
    var courtyardRightEntryX: Float { 22.0 }
    var courtyardStreetTurnOffset: Float { 12.0 }
    var courtyardStreetDepartureOffset: Float { 22.0 }

    func makeCourtyardAccessPlan(directionLeftToRight: Bool) -> CourtyardAccessPlan {
        let entrySide: CourtyardHiddenSide = directionLeftToRight ? .left : .right
        let exitSide = CourtyardHiddenSide.allCases.randomElement() ?? (directionLeftToRight ? .right : .left)
        return makeCourtyardAccessPlan(entrySide: entrySide, exitSide: exitSide, parkingPoint: nil)
    }

    func makeCourtyardAccessPlan(
        entrySide: CourtyardHiddenSide,
        exitSide: CourtyardHiddenSide,
        parkingPoint explicitParkingPoint: OutdoorWorldPoint?
    ) -> CourtyardAccessPlan {
        let entryTurnPoint = streetTurnPoint(for: entrySide)
        let entryPoint = hiddenEntryPoint(for: entrySide)
        let exitPoint = hiddenEntryPoint(for: exitSide)
        let streetExitPoint = streetTurnPoint(for: exitSide)

        let parkingXRange: ClosedRange<Float>
        switch entrySide {
        case .left:
            parkingXRange = (-10.0)...14.0
        case .right:
            parkingXRange = (-14.0)...10.0
        }
        let parkingPoint = explicitParkingPoint ?? OutdoorWorldPoint(
            x: Float.random(in: parkingXRange),
            z: Float.random(in: 2.4...5.4)
        )

        let streetDepartureX = exitSide == .left
            ? streetExitPoint.x - courtyardStreetDepartureOffset
            : streetExitPoint.x + courtyardStreetDepartureOffset

        return CourtyardAccessPlan(
            entrySide: entrySide,
            exitSide: exitSide,
            streetEntryTurnPoint: entryTurnPoint,
            courtyardEntryPoint: entryPoint,
            parkingPoint: parkingPoint,
            courtyardExitPoint: exitPoint,
            streetExitPoint: streetExitPoint,
            streetDeparturePoint: OutdoorWorldPoint(x: streetDepartureX, z: courtyardMainStreetLaneZ)
        )
    }

    func debugCourtyardAccessPlan(for scenario: DebugScenario) -> CourtyardAccessPlan {
        switch scenario {
        case .parkedCar:
            return makeCourtyardAccessPlan(
                entrySide: .left,
                exitSide: .right,
                parkingPoint: OutdoorWorldPoint(x: -4.5, z: 3.4)
            )
        case .approachingCar:
            return makeCourtyardAccessPlan(
                entrySide: .left,
                exitSide: .right,
                parkingPoint: OutdoorWorldPoint(x: 7.0, z: 3.8)
            )
        case .departingCar:
            return makeCourtyardAccessPlan(
                entrySide: .left,
                exitSide: .right,
                parkingPoint: OutdoorWorldPoint(x: -2.0, z: 3.6)
            )
        case .mainStreetEntryLeft:
            return makeCourtyardAccessPlan(
                entrySide: .left,
                exitSide: .right,
                parkingPoint: OutdoorWorldPoint(x: 8.0, z: 4.0)
            )
        case .mainStreetEntryRight:
            return makeCourtyardAccessPlan(
                entrySide: .right,
                exitSide: .left,
                parkingPoint: OutdoorWorldPoint(x: -8.0, z: 4.0)
            )
        case .mainStreetExit:
            return makeCourtyardAccessPlan(
                entrySide: .left,
                exitSide: .right,
                parkingPoint: OutdoorWorldPoint(x: 3.0, z: 3.7)
            )
        }
    }

    func debugStartPhase(for scenario: DebugScenario) -> TrafficLifecycle.StartPhase {
        switch scenario {
        case .parkedCar:
            return .parked
        case .approachingCar:
            return .courtyardEntry
        case .mainStreetEntryLeft, .mainStreetEntryRight:
            return .streetApproach
        case .departingCar, .mainStreetExit:
            return .courtyardExit
        }
    }

    func debugStartPoint(for scenario: DebugScenario, plan: CourtyardAccessPlan) -> OutdoorWorldPoint {
        switch scenario {
        case .parkedCar:
            return plan.parkingPoint
        case .approachingCar:
            return plan.courtyardEntryPoint
        case .mainStreetEntryLeft, .mainStreetEntryRight:
            return OutdoorWorldPoint(
                x: plan.entrySide == .left ? -46.0 : 46.0,
                z: courtyardMainStreetLaneZ
            )
        case .departingCar, .mainStreetExit:
            return plan.parkingPoint
        }
    }

    func debugParkHoldDuration(for scenario: DebugScenario) -> Float {
        switch scenario {
        case .parkedCar:
            return 600
        case .approachingCar, .mainStreetEntryLeft, .mainStreetEntryRight:
            return 600
        case .departingCar, .mainStreetExit:
            return 0.1
        }
    }

    func hiddenEntryPoint(for side: CourtyardHiddenSide) -> OutdoorWorldPoint {
        OutdoorWorldPoint(
            x: side == .left ? courtyardLeftEntryX : courtyardRightEntryX,
            z: courtyardHiddenEntryZ
        )
    }

    func streetTurnPoint(for side: CourtyardHiddenSide) -> OutdoorWorldPoint {
        let x = side == .left
            ? courtyardLeftEntryX - courtyardStreetTurnOffset
            : courtyardRightEntryX + courtyardStreetTurnOffset
        return OutdoorWorldPoint(x: x, z: courtyardMainStreetLaneZ)
    }

    func outdoorWorldPoint(for roomID: RoomID, position: GridPosition) -> OutdoorWorldPoint {
        switch roomID {
        case .street:
            let x = (Float(position.x) / 14.0) * 68.0 - 34.0
            let z = Float(7 - position.y) * 2.5
            return OutdoorWorldPoint(x: x, z: z)
        case .mainStreet:
            let x = (Float(position.x) / 20.0) * 96.0 - 48.0
            let z = 23.5 + (Float(18 - position.y) / 18.0) * 18.0
            return OutdoorWorldPoint(x: x, z: z)
        default:
            return OutdoorWorldPoint(x: 0, z: 0)
        }
    }

    func listenerOutdoorWorldPoint() -> OutdoorWorldPoint {
        outdoorWorldPoint(for: listenerOutdoorRoomID, position: listenerStreetPosition)
    }

    func advanceCourtyardRoutePosition(
        for object: TrafficObject,
        current: OutdoorWorldPoint,
        speed: Float,
        lifecycle: TrafficLifecycle,
        deltaTime: Float
    ) -> OutdoorWorldPoint {
        guard let plan = object.courtyardAccessPlan else {
            return current
        }

        if lifecycle.isParked {
            return plan.parkingPoint
        }

        let target: OutdoorWorldPoint
        if lifecycle.isStreetApproach {
            target = plan.streetEntryTurnPoint
        } else if lifecycle.isCourtyardEntry {
            target = plan.courtyardEntryPoint
        } else if lifecycle.isCourtyardCruise {
            target = plan.parkingPoint
        } else if lifecycle.isCourtyardExit {
            target = plan.courtyardExitPoint
        } else if lifecycle.isStreetDeparture {
            if isNear(current, to: plan.streetExitPoint, threshold: 1.0) {
                target = plan.streetDeparturePoint
            } else {
                target = plan.streetExitPoint
            }
        } else {
            return current
        }

        let next = move(current, toward: target, speed: speed, deltaTime: deltaTime)

        if lifecycle.isStreetApproach, isNear(next, to: plan.streetEntryTurnPoint, threshold: 0.9) {
            _ = lifecycle.beginCourtyardEntry()
            return plan.streetEntryTurnPoint
        }

        if lifecycle.isCourtyardEntry, isNear(next, to: plan.courtyardEntryPoint, threshold: 0.8) {
            _ = lifecycle.beginCourtyardCruise()
            return plan.courtyardEntryPoint
        }

        if lifecycle.isCourtyardExit, isNear(next, to: plan.courtyardExitPoint, threshold: 0.8) {
            _ = lifecycle.beginStreetDeparture()
            return plan.courtyardExitPoint
        }

        return next
    }

    func desiredCourtyardRouteSpeed(
        for object: TrafficObject,
        position: OutdoorWorldPoint,
        lifecycle: TrafficLifecycle
    ) -> Float {
        guard let plan = object.courtyardAccessPlan else {
            return object.cruiseSpeed
        }

        if lifecycle.isParked {
            return 0
        }

        if lifecycle.isStreetApproach {
            let mix = progress(from: object.startX, to: plan.streetEntryTurnPoint.x, value: position.x, leftToRight: object.directionLeftToRight)
            return trafficInterpolate(from: object.cruiseSpeed * 0.92, to: object.cruiseSpeed, progress: mix)
        }

        if lifecycle.isCourtyardEntry {
            return max(object.brakeTargetSpeed * 1.8, object.cruiseSpeed * 0.58)
        }

        if lifecycle.isCourtyardCruise {
            let distance = distance(from: position, to: plan.parkingPoint)
            let parkingMix = 1 - min(1.0, distance / 14.0)
            return trafficInterpolate(from: object.cruiseSpeed * 0.62, to: 0, progress: pow(parkingMix, 1.7))
        }

        if lifecycle.isCourtyardExit {
            let distance = distance(from: position, to: plan.courtyardExitPoint)
            let exitMix = 1 - min(1.0, distance / 14.0)
            return trafficInterpolate(from: max(0.42, object.brakeTargetSpeed), to: object.cruiseSpeed * 0.72, progress: exitMix)
        }

        if lifecycle.isStreetDeparture {
            let distance = distance(from: position, to: plan.streetDeparturePoint)
            let streetMix = 1 - min(1.0, distance / 18.0)
            return trafficInterpolate(from: object.cruiseSpeed * 0.78, to: object.maxSpeed * 0.92, progress: streetMix)
        }

        return object.cruiseSpeed
    }

    func hasReachedCourtyardParkingStop(
        for object: TrafficObject,
        position: OutdoorWorldPoint,
        speed: Float,
        previousSpeed: Float,
        elapsed: Float
    ) -> Bool {
        guard let plan = object.courtyardAccessPlan else { return false }
        let closeEnough = distance(from: position, to: plan.parkingPoint) <= 1.2
        let slowEnough = speed <= max(Self.parkingStopSpeedThreshold, object.brakeTargetSpeed * 0.34)
        let settledEnough = previousSpeed <= max(0.18, object.brakeTargetSpeed * 1.05)
        return closeEnough && slowEnough && settledEnough && elapsed >= Self.minimumParkingApproachTime
    }

    func hasCompletedCourtyardRoute(
        for object: TrafficObject,
        position: OutdoorWorldPoint,
        lifecycle: TrafficLifecycle
    ) -> Bool {
        guard lifecycle.isStreetDeparture, let plan = object.courtyardAccessPlan else {
            return false
        }

        return isNear(position, to: plan.streetDeparturePoint, threshold: 1.2)
    }

    func move(_ current: OutdoorWorldPoint, toward target: OutdoorWorldPoint, speed: Float, deltaTime: Float) -> OutdoorWorldPoint {
        let dx = target.x - current.x
        let dz = target.z - current.z
        let totalDistance = sqrt((dx * dx) + (dz * dz))

        guard totalDistance > 0.0001 else {
            return target
        }

        let step = min(totalDistance, max(0, speed * deltaTime))
        let ratio = step / totalDistance
        return OutdoorWorldPoint(
            x: current.x + dx * ratio,
            z: current.z + dz * ratio
        )
    }

    func isNear(_ current: OutdoorWorldPoint, to target: OutdoorWorldPoint, threshold: Float) -> Bool {
        distance(from: current, to: target) <= threshold
    }

    func distance(from first: OutdoorWorldPoint, to second: OutdoorWorldPoint) -> Float {
        let dx = second.x - first.x
        let dz = second.z - first.z
        return sqrt((dx * dx) + (dz * dz))
    }

    func progress(from start: Float, to end: Float, value: Float, leftToRight: Bool) -> Float {
        let total = max(0.001, abs(end - start))
        let covered = leftToRight ? (value - start) : (start - value)
        return max(0, min(1, covered / total))
    }
}
