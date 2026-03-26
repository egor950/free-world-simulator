import Foundation

enum DriveableVehicleKind: String, CaseIterable {
    case light
    case sedan
    case sport
    case coupe
    case roadster

    var title: String {
        switch self {
        case .light:
            return "легковая машина"
        case .sedan:
            return "седан"
        case .sport:
            return "спортивная машина"
        case .coupe:
            return "купе"
        case .roadster:
            return "родстер"
        }
    }
}

enum DriveEngineState: String {
    case off
    case starting
    case running
}

enum ControlledCarPhase: String {
    case onFoot
    case carDoorOpeningForEnter
    case enteringVehicle
    case carDoorClosingAfterEnter
    case engineStarting
    case engineIdle
    case driving
    case parked
    case carDoorOpeningForExit
    case exitingVehicle
    case carDoorClosingAfterExit
}

struct OutdoorCarWorldPosition: Equatable {
    var x: Float
    var z: Float
}

struct DriveableVehicleBlueprint {
    let kind: DriveableVehicleKind
    let title: String
    let maxSpeed: Double
    let acceleration: Double
    let idleEngineHz: Double
    let maxEngineHz: Double
    let gearShiftEngineHz: Double
    let gearCount: Int
    let steeringBase: Double
    let steeringSpeedFactor: Double
    let engineCue: AudioCueID
    let startupCue: AudioCueID

    static func blueprint(for kind: DriveableVehicleKind) -> DriveableVehicleBlueprint {
        switch kind {
        case .light:
            return DriveableVehicleBlueprint(
                kind: .light,
                title: "легковая машина",
                maxSpeed: 43.0,
                acceleration: 5.1,
                idleEngineHz: 11_025,
                maxEngineHz: 52_000,
                gearShiftEngineHz: 36_000,
                gearCount: 5,
                steeringBase: 220,
                steeringSpeedFactor: 95,
                engineCue: .playerEngineLight,
                startupCue: .playerStartLight
            )
        case .sedan:
            return DriveableVehicleBlueprint(
                kind: .sedan,
                title: "седан",
                maxSpeed: 46.0,
                acceleration: 5.3,
                idleEngineHz: 11_025,
                maxEngineHz: 56_000,
                gearShiftEngineHz: 39_000,
                gearCount: 5,
                steeringBase: 212,
                steeringSpeedFactor: 94,
                engineCue: .playerEngineSedan,
                startupCue: .playerStartSedan
            )
        case .sport:
            return DriveableVehicleBlueprint(
                kind: .sport,
                title: "спортивная машина",
                maxSpeed: 52.0,
                acceleration: 6.1,
                idleEngineHz: 11_025,
                maxEngineHz: 45_500,
                gearShiftEngineHz: 32_900,
                gearCount: 6,
                steeringBase: 198,
                steeringSpeedFactor: 92,
                engineCue: .playerEngineSport,
                startupCue: .playerStartSport
            )
        case .coupe:
            return DriveableVehicleBlueprint(
                kind: .coupe,
                title: "купе",
                maxSpeed: 49.0,
                acceleration: 5.7,
                idleEngineHz: 11_025,
                maxEngineHz: 60_000,
                gearShiftEngineHz: 43_000,
                gearCount: 6,
                steeringBase: 202,
                steeringSpeedFactor: 93,
                engineCue: .playerEngineCoupe,
                startupCue: .playerStartCoupe
            )
        case .roadster:
            return DriveableVehicleBlueprint(
                kind: .roadster,
                title: "родстер",
                maxSpeed: 47.0,
                acceleration: 5.5,
                idleEngineHz: 11_025,
                maxEngineHz: 62_000,
                gearShiftEngineHz: 45_000,
                gearCount: 6,
                steeringBase: 208,
                steeringSpeedFactor: 93,
                engineCue: .trafficEngineRoadster,
                startupCue: .playerStartSedan
            )
        }
    }
}

struct ParkedOwnedCarState: Equatable {
    let id: UUID
    let kind: DriveableVehicleKind
    let title: String
    var roomID: RoomID
    var worldPosition: OutdoorCarWorldPosition
    var gridPosition: GridPosition
    var headingRadians: Double
    var directionLeftToRight: Bool
    var isEngineRunning: Bool
}

struct ControlledCarState: Equatable {
    let id: UUID
    let kind: DriveableVehicleKind
    let title: String
    var roomID: RoomID
    var worldPosition: OutdoorCarWorldPosition
    var headingRadians: Double
    var speed: Double
    var steeringAxis: Double
    var directionLeftToRight: Bool
    var engineState: DriveEngineState
    var phase: ControlledCarPhase
}
