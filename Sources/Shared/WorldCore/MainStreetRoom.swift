import Foundation

enum MainStreetRoom {
    static let gateDoorID = "mainStreet.gate.street"
    static let groceryDoorID = "mainStreet.door.groceryStore"
    static let width = 81
    static let height = 81
    static let gatePosition = GridPosition(x: width / 2, y: height - 1)
    static let centerPosition = GridPosition(x: width / 2, y: height / 2)
    static let groceryDoorMidY = 62
    static let groceryDoorPosition = GridPosition(x: width - 1, y: groceryDoorMidY)
    static let groceryDoorUpperPosition = GridPosition(x: width - 1, y: groceryDoorMidY - 1)
    static let groceryDoorLowerPosition = GridPosition(x: width - 1, y: groceryDoorMidY + 1)
    static let groceryFacadeNorth = GridPosition(x: width - 1, y: 50)
    static let groceryFacadeSouth = GridPosition(x: width - 1, y: 74)
    static let groceryFuturePosition = GridPosition(x: width - 18, y: groceryDoorMidY)
    static let groceryApproachPosition = GridPosition(x: width / 2, y: groceryDoorMidY)
    static var groceryDoorPositions: [GridPosition] {
        (-3...3).map { offset in
            GridPosition(x: width - 1, y: groceryDoorMidY + offset)
        }
    }

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
        let groceryDoor = DoorDefinition(
            id: groceryDoorID,
            name: "дверь продуктового",
            targetRoomID: .groceryStore,
            targetRoomPosition: GroceryStoreRoom.entryPosition,
            state: .closed,
            focusNodeID: "mainStreet.node.groceryDoor",
            shortPrompt: "Справа вход в продуктовый.",
            openResultText: "Ты открыл дверь и можешь войти в продуктовый.",
            lockedText: "Магазин сейчас закрыт.",
            sound: nil
        )

        let groceryDoorNodes = groceryDoorPositions.enumerated().map { index, position in
            FocusNode(
                id: index == 3 ? groceryDoor.focusNodeID : "mainStreet.node.groceryDoor.\(index)",
                title: groceryDoor.name,
                position: position,
                target: .door(groceryDoor.id),
                shortPrompt: "Рядом широкий вход в продуктовый. Если дверь открыта, нажми вправо, чтобы войти.",
                fullDescription: "Ты стоишь у широкого входа в продуктовый. Дверь здесь занимает заметную часть фасада."
            )
        }

        return RoomDefinition(
            id: .mainStreet,
            title: "Улица",
            entryAnnouncement: "Ты вышел на большую улицу. Справа дальше тянется большой фасад продуктового, но теперь до него уже не вечность идти.",
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
                    position: GridPosition(x: width / 2, y: 0),
                    fullDescription: "Ты дошел до дальнего конца этой улицы. Дальше потом пойдет продолжение города."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.left",
                    title: "левый край улицы",
                    position: GridPosition(x: 0, y: height / 2),
                    fullDescription: "Ты у левого края улицы. Здесь потом можно будет разместить дома, витрины и другие места."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.right",
                    title: "правый край улицы",
                    position: GridPosition(x: width - 1, y: height / 2),
                    fullDescription: "Ты у правого края улицы. Здесь фасады, двери и витрины тянутся вдоль всей стороны."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.leftFuture",
                    title: "место под будущие здания",
                    position: GridPosition(x: 18, y: height / 2),
                    fullDescription: "Слева вдоль улицы тянется свободное место под будущие дома, магазины и входы."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.rightFuture",
                    title: "место под будущие здания",
                    position: groceryFuturePosition,
                    fullDescription: "Справа уже чувствуется длинный фасад магазина. До двери осталось не так уж далеко."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.groceryApproach",
                    title: "напротив продуктового",
                    position: groceryApproachPosition,
                    fullDescription: "Ты дошел до уровня продуктового. Теперь иди вправо к фасаду, а потом вдоль стены к двери, если понадобится."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.groceryFacadeNorth",
                    title: "фасад продуктового",
                    position: groceryFacadeNorth,
                    fullDescription: "Справа вдоль улицы тянется длинная стена продуктового. Витрина и фасад идут еще дальше."
                ),
                FocusNode.floor(
                    id: "mainStreet.node.groceryFacadeSouth",
                    title: "фасад продуктового",
                    position: groceryFacadeSouth,
                    fullDescription: "Ты идешь вдоль длинного фасада продуктового. Дверь находится где-то посередине этого здания."
                )
            ] + groceryDoorNodes,
            doors: [
                gateDoor.id: gateDoor,
                groceryDoor.id: groceryDoor
            ],
            items: [:],
            spawnPosition: gatePosition
        )
    }
}
