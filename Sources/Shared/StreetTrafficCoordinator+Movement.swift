@preconcurrency import AVFoundation
import Foundation

extension StreetTrafficCoordinator {

    func trafficZ(for object: TrafficObject, x: Float, isParked: Bool) -> Float {
        guard object.routeStyle == .courtyardParking else { return object.roadZ }
        if isParked { return object.nearZ }
        let approachMix = 1 - min(1.0, abs(x - object.endX) / 12.0)
        return trafficInterpolate(from: object.roadZ, to: object.nearZ, progress: max(0, approachMix))
    }

    func trafficPan(for object: TrafficObject, x: Float, z: Float) -> Float {
        let listenerX = listenerOutdoorWorldPoint().x
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

    func trafficVolume(for object: TrafficObject, x: Float, z: Float, speed: Float, isParked: Bool) -> Float {
        if isParked {
            return 0
        }

        let listenerPoint = listenerOutdoorWorldPoint()
        let listenerX = listenerPoint.x
        let listenerZ = listenerPoint.z
        let dx = x - listenerX
        let dz = z - listenerZ
        let distance = sqrt((dx * dx) + (dz * dz))
        let audibleRadius: Float = object.routeStyle == .courtyardParking ? 30 : 42
        let distanceFade = max(0, 1 - (distance / audibleRadius))
        let distanceMix = pow(distanceFade, 1.8)
        let motionBoost = min(1.0, 0.48 + (speed / max(0.1, object.maxSpeed)) * 0.94)
        let travelDistance = max(1, abs(object.finalExitX - object.startX))
        let traveled = abs(x - object.startX)
        let remaining = abs(object.finalExitX - x)
        let usesInteriorDebugStart = object.routeStyle == .courtyardParking && object.startPhase != .streetApproach
        let fadeInDistance = usesInteriorDebugStart ? max(8, traveled) : traveled
        let fadeIn = min(1.0, fadeInDistance / max(6, travelDistance * 0.18))
        let fadeOut = min(1.0, remaining / max(7, travelDistance * 0.16))
        let routeFade: Float
        if usesInteriorDebugStart {
            routeFade = max(0.76, min(fadeIn, fadeOut))
        } else {
            routeFade = min(fadeIn, fadeOut)
        }
        let routeBoost: Float
        switch object.routeStyle {
        case .roadPass:
            routeBoost = listenerOutdoorRoomID == .street ? 0.9 : 1.04
        case .slowRollBy:
            routeBoost = listenerOutdoorRoomID == .street ? 0.96 : 1.08
        case .courtyardParking:
            if listenerOutdoorRoomID == .mainStreet, !isParked {
                routeBoost = 0.94
            } else if listenerOutdoorRoomID == .street, !isParked, z >= courtyardMainStreetLaneZ - 1 {
                routeBoost = 0.72
            } else {
                routeBoost = 1.05
            }
        }
        return min(1.0, object.baseVolume * motionBoost * routeBoost * distanceMix * routeFade)
    }

    func roadDepth(for distance: TrafficDistanceBand) -> Float {
        switch distance {
        case .close:
            return 24
        case .medium:
            return 30
        case .far:
            return 36
        }
    }

    func syncCourtyardParkingSnapshot(
        for object: TrafficObject,
        x: Float,
        z: Float,
        lifecycle: TrafficLifecycle
    ) {
        if lifecycle.isDeparting {
            updateStreetCarSnapshot(for: object, x: x, z: z, isParked: false, isLeaving: true)
            return
        }

        if lifecycle.isParked {
            updateStreetCarSnapshot(for: object, x: x, z: z, isParked: true, isLeaving: false)
            return
        }

        updateStreetCarSnapshot(for: object, x: x, z: z, isParked: false, isLeaving: false)
    }

    func hasCompletedRoute(
        for object: TrafficObject,
        x: Float,
        z: Float,
        lifecycle: TrafficLifecycle
    ) -> Bool {
        if lifecycle.isParkingRoute {
            return hasCompletedCourtyardRoute(
                for: object,
                position: OutdoorWorldPoint(x: x, z: z),
                lifecycle: lifecycle
            )
        }

        let exitX = object.finalExitX
        return object.directionLeftToRight ? x >= exitX : x <= exitX
    }

    func updateStreetCarSnapshot(for object: TrafficObject, x: Float, z: Float, isParked: Bool, isLeaving: Bool) {
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
            shortPrompt = "\(hint) \(title). Она припаркована во дворе."
            fullDescription = "Перед тобой \(title). \(streetCarAppearanceDescription(for: object.profile.cue)) Она просто стоит во дворе. Если подойти ближе, хорошо чувствуются двери, стекла и линия капота."
        } else if object.routeStyle == .courtyardParking {
            shortPrompt = "\(hint) \(title). Она заезжает во двор."
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
            worldPosition: OutdoorCarWorldPosition(x: x, z: z),
            directionLeftToRight: object.directionLeftToRight,
            vehicleKind: vehicleKind(for: object.profile.cue),
            isParked: isParked,
            isInspectable: isInspectable
        )
    }

    func clearStreetCarSnapshot(for id: UUID) {
        activeStreetCarSnapshots[id] = nil
    }

    func streetGridPosition(
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

    func streetGridPositionForWorldPoint(x: Float, z: Float) -> GridPosition {
        let gridX = Int(round(((x + 34) / 68) * 14))
        let gridY = Int(round(7 - (z / 2.5)))
        return GridPosition(
            x: min(14, max(0, gridX)),
            y: min(14, max(0, gridY))
        )
    }

    func streetCarAppearanceDescription(for cue: AudioCueID) -> String {
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

    func streetWorldX(for position: GridPosition) -> Float {
        (Float(position.x) / 14.0) * 68.0 - 34.0
    }

    func streetWorldZ(for position: GridPosition) -> Float {
        Float(7 - position.y) * 2.5
    }

    func streetCarTitle(for cue: AudioCueID) -> String {
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

    func vehicleKind(for cue: AudioCueID) -> DriveableVehicleKind {
        switch cue {
        case .trafficEngineLight:
            return .light
        case .trafficEngineSedan:
            return .sedan
        case .trafficEngineSport:
            return .sport
        case .trafficEngineCoupe:
            return .coupe
        case .trafficEngineRoadster:
            return .roadster
        default:
            return .sedan
        }
    }

    func streetCarRelativeHint(x: Float, z: Float) -> String {
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

    func trafficAudioPosition(x: Float, z: Float) -> AVAudio3DPoint {
        AVAudio3DPoint(x: x, y: 0, z: -z)
    }

    func streetListenerWorldPosition(for position: GridPosition?) -> AVAudio3DPoint {
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
