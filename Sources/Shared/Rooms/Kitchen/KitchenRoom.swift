import Foundation

enum KitchenRoom {
    static func make() -> RoomDefinition {
        let fridge = KitchenFridge.make()
        let livingDoor = DoorDefinition(id: "kitchen.door.livingRoom", name: "дверь в гостиную", targetRoomID: .livingRoom, targetRoomPosition: GridPosition(x: 5, y: 1), state: .closed, focusNodeID: "kitchen.node.livingDoor", shortPrompt: "Рядом дверь в гостиную.", openResultText: "Ты открыл дверь и вернулся в гостиную.", lockedText: "Заперто.", sound: nil)
        let bathroomDoor = DoorDefinition(id: "kitchen.door.bathroom", name: "дверь в ванную", targetRoomID: .bathroom, targetRoomPosition: GridPosition(x: 1, y: 1), state: .closed, focusNodeID: "kitchen.node.bathroomDoor", shortPrompt: "Рядом дверь в ванную.", openResultText: "Ты открыл дверь и вошел в ванную.", lockedText: "Заперто.", sound: nil)

        return RoomDefinition(
            id: .kitchen,
            title: "Кухня",
            entryAnnouncement: "Ты на кухне.",
            ambientSound: .ambientRoom01,
            width: 7,
            height: 5,
            nodes: [
                FocusNode(id: livingDoor.focusNodeID, title: livingDoor.name, position: GridPosition(x: 0, y: 1), target: .door(livingDoor.id)),
                FocusNode(id: bathroomDoor.focusNodeID, title: bathroomDoor.name, position: GridPosition(x: 6, y: 1), target: .door(bathroomDoor.id)),
                FocusNode(id: fridge.id, title: fridge.name, position: GridPosition(x: 5, y: 2), target: .item(fridge.id))
            ],
            doors: [
                livingDoor.id: livingDoor,
                bathroomDoor.id: bathroomDoor
            ],
            items: [
                fridge.id: fridge
            ],
            spawnPosition: GridPosition(x: 1, y: 1)
        )
    }
}
