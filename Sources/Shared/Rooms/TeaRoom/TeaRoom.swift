import Foundation

enum TeaRoom {
    static let hallwayDoorID = "teaRoom.door.hallway"
    static let bathroomDoorID = "teaRoom.door.bathroom"

    static func make() -> RoomDefinition {
        let hallwayDoor = DoorDefinition(
            id: hallwayDoorID,
            name: "дверь в прихожую",
            targetRoomID: .hallway,
            targetRoomPosition: GridPosition(x: 5, y: 1),
            state: .closed,
            focusNodeID: "teaRoom.node.hallwayDoor",
            shortPrompt: "Слева дверь обратно в прихожую.",
            openResultText: "Ты открыл дверь и вышел в прихожую.",
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
            entryAnnouncement: "Ты в чайной. Здесь небольшой столик для заваривания чая. Слева дверь в прихожую, справа — в ванную.",
            ambientSound: .ambientRoom01,
            width: 5,
            height: 4,
            nodes: [
                FocusNode(
                    id: hallwayDoor.focusNodeID,
                    title: hallwayDoor.name,
                    position: GridPosition(x: 0, y: 1),
                    target: .door(hallwayDoor.id),
                    shortPrompt: "Слева дверь обратно в прихожую. Если она открыта, нажми влево, чтобы выйти.",
                    fullDescription: "Дверь ведёт обратно в прихожую, где стоит стойка чайного бизнеса."
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
                hallwayDoor.id: hallwayDoor,
                bathroomDoor.id: bathroomDoor
            ],
            items: [
                table.id: table
            ],
            spawnPosition: GridPosition(x: 1, y: 1)
        )
    }
}
