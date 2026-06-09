import Foundation

enum HallwayRoom {
    static let neighborDoorID = "hallway.door.neighbors"
    static let neighborDoorNodeID = "hallway.node.neighborsDoor"

    static func make() -> RoomDefinition {
        let coatRack = HallwayCoatRack.make()
        let teaShop = TeaShop.make()

        let bedroomDoor = DoorDefinition(id: "hallway.door.bedroom", name: "дверь в спальню", targetRoomID: .bedroom, targetRoomPosition: GridPosition(x: 1, y: 1), state: .closed, focusNodeID: "hallway.node.bedroomDoor", shortPrompt: "Рядом дверь в спальню.", openResultText: "Ты открыл дверь и прошел в спальню.", lockedText: "Заперто.", sound: nil)
        let lockedDoor = DoorDefinition(id: "hallway.door.storage", name: "дверь в кладовку", targetRoomID: .hallway, targetRoomPosition: nil, state: .locked, focusNodeID: "hallway.node.storageDoor", shortPrompt: "Рядом дверь в кладовку.", openResultText: "", lockedText: "Заперто.", sound: nil)
        let neighborDoor = DoorDefinition(id: neighborDoorID, name: "входная дверь", targetRoomID: .hallway, targetRoomPosition: nil, state: .closed, focusNodeID: neighborDoorNodeID, shortPrompt: "У самой двери кто-то зло переминается и ждет, когда ты откроешь.", openResultText: "", lockedText: "Сейчас она не открывается.", sound: nil)
        let teaRoomDoor = DoorDefinition(id: "hallway.door.teaRoom", name: "дверь в чайную", targetRoomID: .teaRoom, targetRoomPosition: GridPosition(x: 0, y: 1), state: .closed, focusNodeID: "hallway.node.teaRoomDoor", shortPrompt: "Рядом дверь в чайную.", openResultText: "Ты открыл дверь и зашёл в чайную.", lockedText: "Заперто.", sound: nil)

        return RoomDefinition(
            id: .hallway,
            title: "Прихожая",
            entryAnnouncement: "Ты в прихожей.",
            ambientSound: .ambientRoom01,
            width: 7,
            height: 5,
            nodes: [
                FocusNode(id: neighborDoor.focusNodeID, title: neighborDoor.name, position: GridPosition(x: 1, y: 1), target: .door(neighborDoor.id)),
                FocusNode(id: bedroomDoor.focusNodeID, title: bedroomDoor.name, position: GridPosition(x: 6, y: 1), target: .door(bedroomDoor.id)),
                FocusNode(id: teaRoomDoor.focusNodeID, title: teaRoomDoor.name, position: GridPosition(x: 5, y: 1), target: .door(teaRoomDoor.id)),
                FocusNode(id: coatRack.id, title: coatRack.name, position: GridPosition(x: 3, y: 1), target: .item(coatRack.id)),
                FocusNode(id: teaShop.id, title: teaShop.name, position: GridPosition(x: 4, y: 1), target: .item(teaShop.id)),
                FocusNode(id: lockedDoor.focusNodeID, title: lockedDoor.name, position: GridPosition(x: 0, y: 4), target: .door(lockedDoor.id))
            ],
            doors: [
                neighborDoor.id: neighborDoor,
                bedroomDoor.id: bedroomDoor,
                teaRoomDoor.id: teaRoomDoor,
                lockedDoor.id: lockedDoor
            ],
            items: [
                coatRack.id: coatRack,
                teaShop.id: teaShop
            ],
            spawnPosition: GridPosition(x: 1, y: 1)
        )
    }
}
