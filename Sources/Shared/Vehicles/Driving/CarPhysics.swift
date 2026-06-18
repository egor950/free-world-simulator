import Foundation

extension GameViewModel {
    func computeSteeringPower(
        base: Double,
        speedFactor: Double,
        speedNorm: Double,
        isBraking: Bool
    ) -> Double {
        let steerBase = max(0.45, min(1.28, base / 210.0))
        let topFactor = max(0.05, min(1.0, speedFactor / 100.0))
        let highSpeed = 1.0 - speedNorm * (1.0 - topFactor)
        let brakingPenalty = isBraking ? 0.62 : 1.0
        return steerBase * highSpeed * brakingPenalty
    }

    func constrainControlledCar(_ car: inout ControlledCarState, gateIsOpen: Bool) {
        let previousX = car.worldPosition.x
        let previousZ = car.worldPosition.z
        let isGatePassageZone = car.worldPosition.z > 17.45 && car.worldPosition.z < 23.5

        if gateIsOpen && isGatePassageZone && abs(car.worldPosition.x) <= 13.5 {
            car.worldPosition.x = min(10, max(-10, car.worldPosition.x))
            car.worldPosition.z = min(23.5, max(-17.5, car.worldPosition.z))
        } else if car.worldPosition.z >= 23.5 {
            car.worldPosition.x = min(90, max(-90, car.worldPosition.x))
            car.worldPosition.z = min(53.5, max(23.5, car.worldPosition.z))
        } else {
            car.worldPosition.x = min(34, max(-34, car.worldPosition.x))
            car.worldPosition.z = min(17.5, max(-17.5, car.worldPosition.z))
        }

        if isGatePassageZone {
            if gateIsOpen {
                if abs(car.worldPosition.x) <= 13.5 {
                    car.worldPosition.x = min(10, max(-10, car.worldPosition.x))
                } else {
                    car.worldPosition.z = 17.45
                    if car.speed > 0 {
                        car.speed = 0
                    }
                }
            } else {
                car.worldPosition.z = 17.45
                if car.speed > 0 {
                    car.speed = 0
                }
            }
        }

        if car.worldPosition.x != previousX || car.worldPosition.z != previousZ {
            if car.worldPosition.x == -34 || (car.roomID == .street && car.worldPosition.x == 34) {
                car.speed = min(0, car.speed)
            }
            if car.worldPosition.z == -17.5 || car.worldPosition.z == 53.5 {
                car.speed = min(0, car.speed)
            }
        }
    }

    func moveToward(current: Double, target: Double, maxDelta: Double) -> Double {
        if current < target {
            return min(target, current + maxDelta)
        }
        return max(target, current - maxDelta)
    }

    func controlledCarLanePan(_ car: ControlledCarState) -> Float {
        let targetX = preferredDriveLineX(for: car)
        let span = preferredDriveLineSpan(for: car)
        let offset = Double(car.worldPosition.x) - targetX
        let normalized = max(-1.0, min(1.0, offset / span))
        return Float(normalized)
    }

    func preferredDriveLineX(for car: ControlledCarState) -> Double {
        _ = car
        return 0
    }

    func preferredDriveLineSpan(for car: ControlledCarState) -> Double {
        switch car.roomID {
        case .street:
            return 10
        case .mainStreet:
            return 24
        default:
            return 12
        }
    }
}
