import Foundation

extension GameViewModel {
    func debugSetHeldItem(arguments: [String: Any]) throws -> [String: Any] {
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

    func debugSetItemLocation(arguments: [String: Any]) throws -> [String: Any] {
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

    func debugSetState(arguments: [String: Any]) throws -> [String: Any] {
        let key = try debugResolvedStateKey(arguments: arguments)
        guard let value = arguments["value"] as? String, !value.isEmpty else {
            throw LiveGameBridgeError("Для set_state нужен value.")
        }
        state.setRawItemStage(itemID: key, rawValue: value)
        refreshScreenState()
        return debugRuntimeStatePayload(message: "Состояние \(key) = \(value).")
    }

    func debugClearState(arguments: [String: Any]) throws -> [String: Any] {
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
