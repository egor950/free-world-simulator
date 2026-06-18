import Foundation

extension GameViewModel {
    func debugSetPlayer(arguments: [String: Any]) throws -> [String: Any] {
        var messages: [String] = []

        if let rawRoomID = arguments["roomID"] as? String,
           let roomID = RoomID(rawValue: rawRoomID),
           let room = rooms[roomID] {
            let x = min(max(0, arguments["x"] as? Int ?? state.player.roomPosition.x), room.width - 1)
            let y = min(max(0, arguments["y"] as? Int ?? state.player.roomPosition.y), room.height - 1)
            debugMovePlayer(to: roomID, position: GridPosition(x: x, y: y))
            messages.append("Игрок перенесен в \(roomID.rawValue) \(x),\(y).")
        }

        if let poseRaw = arguments["pose"] as? String {
            switch poseRaw.lowercased() {
            case "standing", "stand":
                setPlayerPose(.standing)
                bedAnchorPosition = nil
                messages.append("Поза игрока: standing.")
            case "lying", "lie":
                if state.player.roomID == .bedroom {
                    setPlayerPose(.lying)
                    bedAnchorPosition = state.player.roomPosition
                    messages.append("Поза игрока: lying.")
                } else {
                    setPlayerPose(.standing)
                    bedAnchorPosition = nil
                    messages.append("Лежать можно только в спальне, поэтому оставил standing.")
                }
            case "crawling", "crawl":
                if state.player.roomID == .bedroom {
                    setPlayerPose(.crawling)
                    bedAnchorPosition = state.player.roomPosition
                    messages.append("Поза игрока: crawling.")
                } else {
                    setPlayerPose(.standing)
                    bedAnchorPosition = nil
                    messages.append("Ползание сейчас привязано к кровати, поэтому вне спальни оставил standing.")
                }
            default:
                break
            }
        }

        refreshScreenState()
        let message = messages.isEmpty ? "Состояние игрока обновлено." : messages.joined(separator: " ")
        return debugRuntimeStatePayload(message: message)
    }

    func debugSetControlledCar(arguments: [String: Any]) throws -> [String: Any] {
        guard var car = state.controlledCar else {
            throw LiveGameBridgeError("Сейчас игрок не в машине.")
        }

        let roomID: RoomID
        if let rawRoomID = arguments["roomID"] as? String,
           let parsed = RoomID(rawValue: rawRoomID) {
            roomID = parsed
        } else {
            roomID = car.roomID
        }

        let worldX: Float
        let worldZ: Float

        if let x = arguments["worldX"] as? Double,
           let z = arguments["worldZ"] as? Double {
            worldX = Float(x)
            worldZ = Float(z)
        } else {
            switch roomID {
            case .street:
                worldX = 0
                worldZ = 10
            case .mainStreet:
                worldX = 0
                worldZ = 26
            default:
                throw LiveGameBridgeError("Для set_controlled_car нужна наружная комната street или mainStreet.")
            }
        }

        car.roomID = roomID
        car.worldPosition = OutdoorCarWorldPosition(x: worldX, z: worldZ)
        car.headingRadians = 0
        car.steeringAxis = 0
        car.speed = 0
        car.phase = .parked
        state.controlledCar = car

        state.player.roomID = roomID
        state.player.roomPosition = gridPosition(for: car.worldPosition, roomID: roomID)
        state.player.focusedTarget = .none
        resetDrivingInput()
        refreshScreenState()

        return debugRuntimeStatePayload(
            message: "Машина игрока перенесена в \(roomID.rawValue) \(Int(worldX.rounded())),\(Int(worldZ.rounded()))."
        )
    }

    func debugSpawnCar() throws -> [String: Any] {
        let roomID = state.player.roomID
        guard roomID == .street || roomID == .mainStreet else {
            throw LiveGameBridgeError("Машину можно заспавнить только на street или mainStreet.")
        }

        let playerPos = state.player.roomPosition
        let worldPos: OutdoorCarWorldPosition
        switch roomID {
        case .mainStreet:
            let x = (Float(playerPos.x) / Float(MainStreetRoom.width - 1)) * 180.0 - 90.0
            let z = 23.5 + (Float((MainStreetRoom.height - 1) - playerPos.y) / Float(MainStreetRoom.height - 1)) * 30.0
            worldPos = OutdoorCarWorldPosition(x: x + 2, z: z)
        case .street:
            worldPos = OutdoorCarWorldPosition(x: (Float(playerPos.x) / 14.0) * 68.0 - 34.0, z: Float(7 - playerPos.y) * 2.5)
        default:
            throw LiveGameBridgeError("Неподдерживаемая комната.")
        }

        let title = "седан"
        let car = ParkedOwnedCarState(
            id: UUID(),
            kind: .sedan,
            title: title,
            roomID: roomID,
            worldPosition: worldPos,
            gridPosition: playerPos,
            headingRadians: roomID == .mainStreet ? .pi / 2 : 0,
            directionLeftToRight: true,
            isEngineRunning: true
        )
        state.setParkedOwnedCar(car)
        refreshScreenState()

        return debugRuntimeStatePayload(message: "Заспавнен \(title) с работающим мотором рядом с игроком.")
    }
}
