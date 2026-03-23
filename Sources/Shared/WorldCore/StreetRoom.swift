import Foundation

enum StreetRoom {
    static let apartmentDoorID = "street.door.apartment"
    static let gateDoorID = "street.gate.mainStreet"
    static let gateTiming = TimedDoorTransitionConfiguration(
        openCue: .gateOpen,
        closeCue: .gateClose,
        openDuration: 2.22,
        closeDuration: 3.40
    )

    static func make() -> RoomDefinition {
        let apartmentDoor = DoorDefinition(
            id: apartmentDoorID,
            name: "дверь обратно в квартиру",
            targetRoomID: .bathroom,
            targetRoomPosition: GridPosition(x: 4, y: 1),
            state: .closed,
            focusNodeID: "street.node.apartmentDoor",
            shortPrompt: "Рядом дверь обратно в квартиру.",
            openResultText: "Ты открыл дверь и можешь вернуться в ванную.",
            lockedText: "Заперто.",
            sound: nil
        )
        let gateDoor = DoorDefinition(
            id: gateDoorID,
            name: "калитка",
            targetRoomID: .mainStreet,
            targetRoomPosition: MainStreetRoom.gatePosition,
            state: .closed,
            focusNodeID: "street.node.gate",
            shortPrompt: "Впереди калитка на большую улицу.",
            openResultText: "Ты открыл калитку и можешь выйти дальше на улицу.",
            lockedText: "Калитка не поддается.",
            sound: nil,
            interactionStyle: .timedGate(gateTiming)
        )

        return RoomDefinition(
            id: .street,
            title: "Улица",
            entryAnnouncement: "Ты вышел на улицу. Здесь пока двор, и можно идти во все четыре стороны. Под ногами асфальт.",
            ambientSound: nil,
            movementMode: .freeGrid4Way,
            stepSurface: .asphalt,
            width: 15,
            height: 15,
            nodes: [
                FocusNode(
                    id: apartmentDoor.focusNodeID,
                    title: apartmentDoor.name,
                    position: GridPosition(x: 7, y: 14),
                    target: .door(apartmentDoor.id),
                    shortPrompt: "Позади тебя вход обратно в квартиру. Если дверь открыта, нажми назад, чтобы войти.",
                    fullDescription: "Перед тобой дверь обратно в квартиру. За ней ванная и вся квартира."
                ),
                FocusNode.floor(
                    id: "street.node.center",
                    title: "асфальт",
                    position: GridPosition(x: 7, y: 7),
                    fullDescription: "Ты стоишь почти в центре двора. Под ногами жесткий асфальт, а вокруг открытое пространство."
                ),
                FocusNode(
                    id: gateDoor.focusNodeID,
                    title: gateDoor.name,
                    position: GridPosition(x: 7, y: 0),
                    target: .door(gateDoor.id),
                    shortPrompt: "Впереди калитка. Если она открыта, нажми вперед, чтобы выйти дальше на улицу.",
                    fullDescription: "Перед тобой калитка. За ней идет более широкая улица."
                ),
                FocusNode.floor(
                    id: "street.node.wall",
                    title: "стена дома",
                    position: GridPosition(x: 0, y: 7),
                    fullDescription: "Слева тянется стена дома. Она держит двор, и дальше прохода нет."
                ),
                FocusNode.floor(
                    id: "street.node.edge",
                    title: "край двора",
                    position: GridPosition(x: 14, y: 7),
                    fullDescription: "Ты дошел до правого края двора. Дальше путь пока закрыт."
                )
            ],
            doors: [
                apartmentDoor.id: apartmentDoor,
                gateDoor.id: gateDoor
            ],
            items: [:],
            spawnPosition: GridPosition(x: 7, y: 14)
        )
    }
}
