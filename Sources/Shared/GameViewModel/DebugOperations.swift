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
            neighbor.startNeighborBreakIn(introText: introText, finalText: finalText)
            return debugRuntimeStatePayload(message: "Штурм соседей запущен.")

        case "neighbor_attack":
            let text = arguments["text"] as? String ?? "Отладка. Сосед подлетел и вырубил игрока."
            let logLine = arguments["logLine"] as? String ?? "Отладка: сосед вырубил игрока"
            neighbor.resolveNeighborAttack(text: text, logLine: logLine)
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
            "responseTaskActive": neighbor.responseTask != nil,
            "breakInTaskActive": neighbor.breakInTask != nil,
            "hitsTarget": neighbor.debug.doorHitsTarget,
            "responsePauseMin": neighbor.debug.responsePauseRange?.lowerBound ?? -1,
            "responsePauseMax": neighbor.debug.responsePauseRange?.upperBound ?? -1,
            "breakInPauseMin": neighbor.debug.breakInPauseRange?.lowerBound ?? -1,
            "breakInPauseMax": neighbor.debug.breakInPauseRange?.upperBound ?? -1,
            "hitsOverride": neighbor.debug.doorHitsTargetOverride ?? -1,
            "footstepCountOverride": neighbor.debug.footstepCountOverride ?? -1,
            "footstepPauseOverride": neighbor.debug.footstepPauseOverride ?? -1
        ]

        payload["debugMessage"] = message ?? ""
        payload["rawState"] = [
            "player": playerState,
            "itemStages": itemStages,
            "itemLocations": itemLocations,
            "neighbor": neighborState,
            "audio": audioCoordinator.debugParkedCarAudioState()
        ]
        return payload
    }
}
