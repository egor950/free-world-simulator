import Foundation

enum MainStreetRoom {
    static let gateDoorID = "mainStreet.gate.street"
    static let width = 41
    static let height = 33
    static let gatePosition = GridPosition(x: 20, y: 32)
    static let centerPosition = GridPosition(x: 20, y: 16)

    static func make() -> RoomDefinition {
        let gateDoor = DoorDefinition(
            id: gateDoorID,
            name: "калитка",
            targetRoomID: .street,
            targetRoomPosition: GridPosition(x: 7, y: 0),
            state: .closed,
            focusNodeID: "mainStreet.node.gate",
            shortPrompt: "Позади калитка обратно во двор.",
            openResultText: "Ты открыл калитку и можешь вернуться во двор.",
            lockedText: "Калитка не поддается.",
            sound: nil,
            interactionStyle: .timedGate(StreetRoom.gateTiming)
        )

        return RoomDefinition(
            id: .mainStreet,
            title: "Улица",
            entryAnnouncement: "Ты вышел дальше на улицу. Здесь уже по-настоящему просторно: улица тянется вперед, назад, влево и вправо, а по сторонам есть место под будущие здания.",
            ambientSound: nil,
            movementMode: .freeGrid4Way,
            stepSurface: .asphalt,
            width: width,
            height: height,
            nodes: [
                FocusNode(
                    id: gateDoor.focusNodeID,
                    title: gateDoor.name,
                    position: gatePosition,
                    target: .door(gateDoor.id),
                    shortPrompt: "Позади калитка обратно во двор. Если она открыта, нажми назад, чтобы вернуться.",
                    fullDescription: "Позади тебя калитка обратно во двор. Через нее можно вернуться к дому и парковке."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.center",
                    title: "асфальт",
                    position: centerPosition,
                    fullDescription: "Ты почти в середине большой улицы. Под ногами асфальт, а вокруг уже чувствуется настоящее городское пространство."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.forward",
                    title: "дальний край улицы",
                    position: GridPosition(x: 20, y: 0),
                    fullDescription: "Ты дошел до дальнего конца этой улицы. Дальше потом пойдет продолжение города."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.left",
                    title: "левый край улицы",
                    position: GridPosition(x: 0, y: 16),
                    fullDescription: "Ты у левого края улицы. Здесь потом можно будет разместить дома, витрины и другие места."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.right",
                    title: "правый край улицы",
                    position: GridPosition(x: 40, y: 16),
                    fullDescription: "Ты у правого края улицы. Здесь тоже есть место под будущие здания и точки назначения."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.leftFuture",
                    title: "место под будущие здания",
                    position: GridPosition(x: 6, y: 15),
                    fullDescription: "Слева вдоль улицы тянется свободное место под будущие дома, магазины и входы."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.rightFuture",
                    title: "место под будущие здания",
                    position: GridPosition(x: 34, y: 15),
                    fullDescription: "Справа вдоль улицы тоже тянется свободное место под будущие дома, магазины и другие городские точки."
                )
            ],
            doors: [
                gateDoor.id: gateDoor
            ],
            items: [:],
            spawnPosition: gatePosition
        )
    }
}
