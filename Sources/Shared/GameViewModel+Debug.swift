import Foundation

extension GameViewModel {
    func debugWorld(operation: String, arguments: [String: Any]) throws -> [String: Any] {
        switch operation {
        case "get_runtime_state":
            return debugRuntimeStatePayload()

        case "set_player":
            return try debugSetPlayer(arguments: arguments)

        case "set_controlled_car":
            return try debugSetControlledCar(arguments: arguments)

        case "set_held_item":
            return try debugSetHeldItem(arguments: arguments)

        case "clear_held_item":
            state.player.heldItem = nil
            refreshScreenState()
            return debugRuntimeStatePayload(message: "Предмет в руках очищен.")

        case "set_item_location":
            return try debugSetItemLocation(arguments: arguments)

        case "clear_item_location":
            guard let itemID = arguments["itemID"] as? String, !itemID.isEmpty else {
                throw LiveGameBridgeError("Для clear_item_location нужен itemID.")
            }
            state.clearItemLocation(itemID: itemID)
            refreshScreenState()
            return debugRuntimeStatePayload(message: "Положение предмета очищено: \(itemID).")

        case "set_state":
            return try debugSetState(arguments: arguments)

        case "clear_state":
            return try debugClearState(arguments: arguments)

        case "neighbor_set_state":
            return try debugSetNeighborState(arguments: arguments)

        case "neighbor_loud_step":
            return debugTriggerNeighborLoudStep()

        case "neighbor_start_break_in":
            let introText = arguments["introText"] as? String ?? "Снаружи сорвались: Всё, ломаем дверь."
            let finalText = arguments["finalText"] as? String ?? "Отладка: соседский штурм запущен."
            startNeighborBreakIn(introText: introText, finalText: finalText)
            return debugRuntimeStatePayload(message: "Штурм соседей запущен.")

        case "neighbor_attack":
            let text = arguments["text"] as? String ?? "Отладка. Сосед подлетел и вырубил игрока."
            let logLine = arguments["logLine"] as? String ?? "Отладка: сосед вырубил игрока"
            resolveNeighborAttack(text: text, logLine: logLine)
            return debugRuntimeStatePayload(message: "Соседская атака выполнена.")

        case "neighbor_set_config":
            return debugSetNeighborConfig(arguments: arguments)

        case "spawn_car":
            return try debugSpawnCar()

        case "refresh":
            refreshScreenState()
            return debugRuntimeStatePayload(message: "Экран и мир обновлены.")

        default:
            throw LiveGameBridgeError("Неизвестная debug-операция: \(operation)")
        }
    }

    func debugRuntimeStatePayload(message: String? = nil) -> [String: Any] {
        var payload = statePayload(recentPhrases: [])
        let itemStages = state.itemStages
            .sorted { $0.key < $1.key }
            .map { ["key": $0.key, "value": $0.value] }
        let itemLocations = state.itemRooms.keys.sorted().map { itemID in
            [
                "itemID": itemID,
                "roomID": state.room(for: itemID)?.rawValue ?? "",
                "x": state.position(for: itemID)?.x ?? -1,
                "y": state.position(for: itemID)?.y ?? -1
            ]
        }
        let playerState: [String: Any] = [
            "roomID": state.player.roomID.rawValue,
            "x": state.player.roomPosition.x,
            "y": state.player.roomPosition.y,
            "pose": String(describing: state.player.pose),
            "focusedTarget": String(describing: state.player.focusedTarget),
            "heldItemID": state.player.heldItem?.itemID ?? "",
            "heldItemName": state.player.heldItem?.name ?? ""
        ]
        let neighborState: [String: Any] = [
            "state": debugNeighborStateName(),
            "responseTaskActive": neighborResponseTask != nil,
            "breakInTaskActive": neighborBreakInTask != nil,
            "hitsTarget": neighborDoorHitsTarget,
            "responsePauseMin": debugNeighborResponsePauseRange?.lowerBound ?? -1,
            "responsePauseMax": debugNeighborResponsePauseRange?.upperBound ?? -1,
            "breakInPauseMin": debugNeighborBreakInPauseRange?.lowerBound ?? -1,
            "breakInPauseMax": debugNeighborBreakInPauseRange?.upperBound ?? -1,
            "hitsOverride": debugNeighborDoorHitsTargetOverride ?? -1,
            "footstepCountOverride": debugNeighborFootstepCountOverride ?? -1,
            "footstepPauseOverride": debugNeighborFootstepPauseOverride ?? -1
        ]

        payload["debugMessage"] = message ?? ""
        payload["rawState"] = [
            "player": playerState,
            "itemStages": itemStages,
            "itemLocations": itemLocations,
            "neighbor": neighborState
        ]
        return payload
    }

    func debugNeighborStateName() -> String {
        if neighborEncounterMachine.isResolved { return "resolved" }
        if neighborEncounterMachine.isBreakInActive { return "breakin" }
        if neighborEncounterMachine.isDoorbellRaised { return "doorbell" }
        if neighborEncounterMachine.isWarned { return "warned" }
        return "calm"
    }

    private func debugSetPlayer(arguments: [String: Any]) throws -> [String: Any] {
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

    private func debugSetControlledCar(arguments: [String: Any]) throws -> [String: Any] {
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

    private func debugSpawnCar() throws -> [String: Any] {
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

    private func debugSetHeldItem(arguments: [String: Any]) throws -> [String: Any] {
        guard let itemID = arguments["itemID"] as? String, !itemID.isEmpty else {
            throw LiveGameBridgeError("Для set_held_item нужен itemID.")
        }

        let itemName = (arguments["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (itemName?.isEmpty == false) ? itemName! : defaultHeldItemName(for: itemID)
        state.player.heldItem = HeldItem(itemID: itemID, name: resolvedName)
        state.clearItemLocation(itemID: itemID)
        refreshScreenState()
        return debugRuntimeStatePayload(message: "Теперь в руках \(resolvedName).")
    }

    private func debugSetItemLocation(arguments: [String: Any]) throws -> [String: Any] {
        guard let itemID = arguments["itemID"] as? String, !itemID.isEmpty else {
            throw LiveGameBridgeError("Для set_item_location нужен itemID.")
        }
        guard let rawRoomID = arguments["roomID"] as? String,
              let roomID = RoomID(rawValue: rawRoomID),
              let room = rooms[roomID] else {
            throw LiveGameBridgeError("Для set_item_location нужна корректная roomID.")
        }

        let x = min(max(0, arguments["x"] as? Int ?? 0), room.width - 1)
        let y = min(max(0, arguments["y"] as? Int ?? 0), room.height - 1)
        state.setItemLocation(itemID: itemID, roomID: roomID, position: GridPosition(x: x, y: y))
        if state.player.heldItem?.itemID == itemID {
            state.player.heldItem = nil
        }
        refreshScreenState()
        return debugRuntimeStatePayload(message: "Предмет \(itemID) перемещен в \(roomID.rawValue) \(x),\(y).")
    }

    private func debugSetState(arguments: [String: Any]) throws -> [String: Any] {
        let key = try debugResolvedStateKey(arguments: arguments)
        guard let value = arguments["value"] as? String, !value.isEmpty else {
            throw LiveGameBridgeError("Для set_state нужен value.")
        }
        state.setRawItemStage(itemID: key, rawValue: value)
        refreshScreenState()
        return debugRuntimeStatePayload(message: "Состояние \(key) = \(value).")
    }

    private func debugClearState(arguments: [String: Any]) throws -> [String: Any] {
        let key = try debugResolvedStateKey(arguments: arguments)
        state.setRawItemStage(itemID: key, rawValue: nil)
        refreshScreenState()
        return debugRuntimeStatePayload(message: "Состояние \(key) очищено.")
    }

    private func debugResolvedStateKey(arguments: [String: Any]) throws -> String {
        if let key = arguments["key"] as? String, !key.isEmpty {
            return key
        }
        if let target = arguments["target"] as? String, !target.isEmpty {
            return debugStageKey(for: target)
        }
        throw LiveGameBridgeError("Нужен key или target.")
    }

    private func debugStageKey(for target: String) -> String {
        switch target.lowercased() {
        case "kettle.water":
            return KitchenKettle.itemID
        case "kettle.lid":
            return KitchenKettle.itemID + ".lid"
        case "kettle.placement":
            return KitchenKettle.itemID + ".placement"
        case "mug.fill":
            return KitchenMug.itemID
        case "stove.stage", "kettle.base", "kettle.base.stage":
            return KitchenStove.itemID
        case "tv.stage":
            return LivingRoomGlassTV.itemID
        case "table.stage":
            return LivingRoomTable.itemID
        case "fridge.stage":
            return KitchenFridge.itemID
        case "mirror.stage":
            return BathroomMirror.itemID
        case "pillow.condition":
            return BedroomPillow.itemID
        default:
            return target
        }
    }

    private func debugSetNeighborState(arguments: [String: Any]) throws -> [String: Any] {
        guard let rawState = arguments["state"] as? String else {
            throw LiveGameBridgeError("Для neighbor_set_state нужен state.")
        }

        cancelNeighborTasks()
        switch rawState.lowercased() {
        case "calm":
            neighborEncounterMachine.resetToCalm()
        case "warn", "warned":
            neighborEncounterMachine.markWarned()
        case "doorbell":
            neighborEncounterMachine.markDoorbellRaised()
        case "breakin", "break_in":
            neighborEncounterMachine.markBreakInStarted()
        case "resolved":
            neighborEncounterMachine.markResolved()
        default:
            throw LiveGameBridgeError("Неизвестное состояние соседа: \(rawState)")
        }

        refreshScreenState()
        return debugRuntimeStatePayload(message: "Сосед переведен в состояние \(debugNeighborStateName()).")
    }

    private func debugTriggerNeighborLoudStep() -> [String: Any] {
        let step = neighborEncounterMachine.resolveLoudAction()
        let result: String

        switch step {
        case .warn:
            result = "Сосед перешел в предупреждение."
        case .ringDoorbell:
            audioCoordinator.playEffect(.doorbellMain)
            scheduleNeighborResponse()
            result = "Сосед поднял дверной звонок."
        case .startBreakIn:
            startNeighborBreakIn(
                introText: "Отладка. Сосед начинает ломать дверь.",
                finalText: "Отладка. Штурм уже запущен."
            )
            result = "Сосед начал штурм."
        case .intensifyBreakIn:
            audioCoordinator.playEffect(.doorBreakHeavy)
            result = "Сосед усилил штурм."
        case .ignore:
            result = "Сосед ничего не сделал."
        }

        refreshScreenState()
        return debugRuntimeStatePayload(message: result)
    }

    private func debugSetNeighborConfig(arguments: [String: Any]) -> [String: Any] {
        if let min = arguments["responsePauseMin"] as? Double,
           let max = arguments["responsePauseMax"] as? Double,
           min > 0, max >= min {
            debugNeighborResponsePauseRange = min...max
        }

        if let min = arguments["breakInPauseMin"] as? Double,
           let max = arguments["breakInPauseMax"] as? Double,
           min > 0, max >= min {
            debugNeighborBreakInPauseRange = min...max
        }

        if let hits = arguments["hitsTarget"] as? Int {
            debugNeighborDoorHitsTargetOverride = max(1, hits)
        }

        if let count = arguments["footstepCount"] as? Int {
            debugNeighborFootstepCountOverride = max(0, count)
        }

        if let pause = arguments["footstepPause"] as? Double {
            debugNeighborFootstepPauseOverride = max(0, pause)
        }

        if (arguments["reset"] as? Bool) == true {
            debugNeighborResponsePauseRange = nil
            debugNeighborBreakInPauseRange = nil
            debugNeighborDoorHitsTargetOverride = nil
            debugNeighborFootstepCountOverride = nil
            debugNeighborFootstepPauseOverride = nil
        }

        return debugRuntimeStatePayload(message: "Отладочная конфигурация соседей обновлена.")
    }

    private func defaultHeldItemName(for itemID: String) -> String {
        switch itemID {
        case KitchenKettle.itemID:
            return "электрический чайник"
        case KitchenMug.itemID:
            return "кружка"
        case BedroomPillow.itemID:
            return "подушка"
        default:
            if let item = rooms.values.lazy.compactMap({ $0.items[itemID] }).first {
                return item.name
            }
            return itemID
        }
    }
}
