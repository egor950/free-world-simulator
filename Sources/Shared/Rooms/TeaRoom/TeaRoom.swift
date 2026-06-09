import Foundation

enum TeaRoom {
    static let kitchenDoorID = "teaRoom.door.kitchen"
    static let bathroomDoorID = "teaRoom.door.bathroom"

    static func make() -> RoomDefinition {
        let kitchenDoor = DoorDefinition(
            id: kitchenDoorID,
            name: "дверь на кухню",
            targetRoomID: .kitchen,
            targetRoomPosition: GridPosition(x: 6, y: 1),
            state: .closed,
            focusNodeID: "teaRoom.node.kitchenDoor",
            shortPrompt: "Слева дверь обратно на кухню.",
            openResultText: "Ты открыл дверь и вышел на кухню.",
            lockedText: "Дверь не открывается.",
            sound: nil
        )
        let bathroomDoor = DoorDefinition(
            id: bathroomDoorID,
            name: "дверь в ванную",
            targetRoomID: .bathroom,
            targetRoomPosition: GridPosition(x: 0, y: 1),
            state: .closed,
            focusNodeID: "teaRoom.node.bathroomDoor",
            shortPrompt: "Справа дверь в ванную.",
            openResultText: "Ты открыл дверь и зашёл в ванную.",
            lockedText: "Дверь не открывается.",
            sound: nil
        )
        let table = TeaRoomTable.make()

        return RoomDefinition(
            id: .teaRoom,
            title: "Чайная",
            entryAnnouncement: "Ты в чайной. Здесь небольшой столик для заваривания чая. Слева дверь на кухню, справа — в ванную.",
            ambientSound: .ambientRoom01,
            width: 5,
            height: 4,
            nodes: [
                FocusNode(
                    id: kitchenDoor.focusNodeID,
                    title: kitchenDoor.name,
                    position: GridPosition(x: 0, y: 1),
                    target: .door(kitchenDoor.id),
                    shortPrompt: "Слева дверь обратно на кухню. Если она открыта, нажми влево, чтобы выйти.",
                    fullDescription: "Дверь ведёт обратно на кухню."
                ),
                FocusNode(
                    id: bathroomDoor.focusNodeID,
                    title: bathroomDoor.name,
                    position: GridPosition(x: 4, y: 1),
                    target: .door(bathroomDoor.id),
                    shortPrompt: "Справа дверь в ванную. Если она открыта, нажми вправо, чтобы выйти.",
                    fullDescription: "Дверь ведёт в ванную комнату с краном и зеркалом."
                ),
                FocusNode(
                    id: table.id,
                    title: table.name,
                    position: GridPosition(x: 2, y: 1),
                    target: .item(table.id)
                )
            ],
            doors: [
                kitchenDoor.id: kitchenDoor,
                bathroomDoor.id: bathroomDoor
            ],
            items: [
                table.id: table
            ],
            spawnPosition: GridPosition(x: 1, y: 1)
        )
    }
}
