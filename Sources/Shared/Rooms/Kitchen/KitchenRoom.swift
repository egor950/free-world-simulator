import Foundation

enum KitchenRoom {
    static func make() -> RoomDefinition {
        let fridge = KitchenFridge.make()
        let kettle = KitchenKettle.make()
        let mug = KitchenMug.make()
        let stove = KitchenStove.make()
        let livingDoor = DoorDefinition(id: "kitchen.door.livingRoom", name: "дверь в гостиную", targetRoomID: .livingRoom, targetRoomPosition: GridPosition(x: 5, y: 1), state: .closed, focusNodeID: "kitchen.node.livingDoor", shortPrompt: "Рядом дверь в гостиную.", openResultText: "Ты открыл дверь и вернулся в гостиную.", lockedText: "Заперто.", sound: .doorCloseKitchen)
        let teaRoomDoor = DoorDefinition(id: "kitchen.door.teaRoom", name: "дверь в чайную", targetRoomID: .teaRoom, targetRoomPosition: GridPosition(x: 0, y: 1), state: .closed, focusNodeID: "kitchen.node.teaRoomDoor", shortPrompt: "Рядом дверь в чайную.", openResultText: "Ты открыл дверь и вошел в чайную.", lockedText: "Заперто.", sound: .doorCloseKitchen)

        return RoomDefinition(
            id: .kitchen,
            title: "Кухня",
            entryAnnouncement: "Ты на кухне.",
            ambientSound: .ambientRoom01,
            width: 7,
            height: 5,
            nodes: [
                FocusNode(id: livingDoor.focusNodeID, title: livingDoor.name, position: GridPosition(x: 0, y: 1), target: .door(livingDoor.id)),
                FocusNode(id: teaRoomDoor.focusNodeID, title: teaRoomDoor.name, position: GridPosition(x: 6, y: 1), target: .door(teaRoomDoor.id)),
                FocusNode(id: mug.id, title: mug.name, position: GridPosition(x: 2, y: 1), target: .item(mug.id)),
                FocusNode(id: stove.id, title: stove.name, position: GridPosition(x: 3, y: 1), target: .item(stove.id)),
                FocusNode(id: kettle.id, title: kettle.name, position: GridPosition(x: 4, y: 2), target: .item(kettle.id)),
                FocusNode(id: fridge.id, title: fridge.name, position: GridPosition(x: 5, y: 2), target: .item(fridge.id))
            ],
            doors: [
                livingDoor.id: livingDoor,
                teaRoomDoor.id: teaRoomDoor
            ],
            items: [
                kettle.id: kettle,
                mug.id: mug,
                stove.id: stove,
                fridge.id: fridge
            ],
            spawnPosition: GridPosition(x: 1, y: 1)
        )
    }
}
