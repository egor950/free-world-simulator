import Foundation

extension GameViewModel {
    func roomEmptyDescription() -> String {
        if state.controlledCar != nil {
            return "Ты за рулем. Сейчас важнее дорога, скорость и машина, а не пешая точка в комнате."
        }

        if currentRoom.id == .street {
            return streetEmptyDescription()
        }

        if currentRoom.id == .mainStreet {
            return mainStreetEmptyDescription()
        }

        if currentRoom.id == .groceryStore {
            return groceryStoreEmptyDescription()
        }

        if currentRoom.id == .hallway {
            return hallwayEmptyDescription()
        }

        let nearestDistance = visibleNodes.map { manhattanDistance(from: $0.position, to: state.player.roomPosition) }.min() ?? (currentRoom.width + currentRoom.height)

        if nearestDistance >= 4 {
            return "Ты стоишь в свободной части комнаты. Здесь идешь по дорожке комнаты, а под ногами мягкое покрытие. До ближайшего предмета или двери еще несколько шагов."
        }

        return "Ты в свободной части комнаты. Здесь движение идет по дорожке комнаты, а рядом уже есть дверь или предмет."
    }

    func hallwayEmptyDescription() -> String {
        let pos = state.player.roomPosition

        if pos == GridPosition(x: 1, y: 1) {
            return "Ты стоишь в первой комнате у входа. Спальня слева, а если идти вправо, выйдешь в середину прихожей."
        }

        if pos.y == 1 && pos.x < 3 {
            return "Ты идешь по верхней части прихожей вправо. Справа еще есть свободное место."
        }

        if pos.y == 1 && pos.x > 3 {
            return "Ты уже в правой части прихожей. Недалеко отсюда дверь в гостиную."
        }

        if pos.y >= 3 && pos.x >= 4 {
            return "Ты в нижней правой части прихожей. Здесь рядом кухня, а дальше по низу можно выйти к ванной."
        }

        if pos.y >= 3 && pos.x <= 1 {
            return "Ты в нижней левой части прихожей. Здесь тихий угол, рядом кладовка."
        }

        return "Ты в центре первой комнаты. Отсюда можно уходить вперед, назад, влево и вправо по всей прихожей."
    }

    func streetEmptyDescription() -> String {
        let pos = state.player.roomPosition

        if pos == GridPosition(x: 7, y: 14) {
            return "Ты стоишь у двери обратно в квартиру. Позади вход, а впереди двор. Здесь можно идти во все четыре стороны. Под ногами асфальт."
        }

        if pos == GridPosition(x: 7, y: 0) {
            return "Ты у калитки в верхней части двора. За ней идет более широкая улица."
        }

        if pos.y <= 2 {
            return "Ты почти у дороги. Впереди идет поток машин, а под ногами жесткий асфальт."
        }

        if pos.x <= 2 {
            return "Ты у левой стороны двора, рядом стена дома. Здесь улица открыта вверх, вниз и вправо."
        }

        if pos.x >= currentRoom.width - 3 {
            return "Ты у правого края двора. Слева открыто пространство, а дальше вправо пути пока нет."
        }

        if let nearestCarDistance = streetCarSnapshots
            .filter(\.isInspectable)
            .map({ manhattanDistance(from: $0.position, to: pos) })
            .min(), nearestCarDistance <= 2 {
            return "Ты во дворе. Совсем рядом машина, к ней можно подойти еще ближе."
        }

        if let hint = nearestStreetCarGuidance(maxDistance: 8, includeDistance: true, parkedOnly: true) {
            return "Ты во дворе. \(hint)"
        }

        return "Ты во дворе. Здесь можно свободно идти вверх, вниз, влево и вправо."
    }

    func mainStreetEmptyDescription() -> String {
        let pos = state.player.roomPosition
        let leftBand = 14
        let rightBand = currentRoom.width - 15
        let storefrontBandStart = MainStreetRoom.groceryFacadeNorth.y - 6
        let storefrontBandEnd = MainStreetRoom.groceryFacadeSouth.y + 6

        if pos == MainStreetRoom.gatePosition {
            return "Ты стоишь сразу за калиткой. Позади двор, а впереди уже большая улица. Здесь заметно больше пространства."
        }

        if pos.y <= 8 {
            return "Ты почти у дальнего конца улицы. Дальше потом пойдет продолжение города."
        }

        if pos.x <= 8 {
            return "Ты у левого края большой улицы. Здесь потом можно будет разместить дома, витрины и другие места."
        }

        if pos.x >= currentRoom.width - 9 {
            if storefrontBandStart...storefrontBandEnd ~= pos.y {
                return "Ты идешь вдоль большого фасада продуктового. Где-то рядом вход в магазин."
            }
            return "Ты у правого края большой улицы. Здесь тоже есть место под будущие здания и точки назначения."
        }

        if pos.x <= leftBand {
            return "Ты идешь по большой улице. Слева тянется свободная линия под будущие дома и магазины."
        }

        if pos.x >= rightBand {
            if storefrontBandStart...storefrontBandEnd ~= pos.y {
                return "Ты идешь рядом с продуктовым. Вдоль стены тянется длинный фасад, а дверь находится в средней части здания."
            }
            return "Ты идешь по большой улице. Справа тянется линия фасадов и будущих входов."
        }

        if pos.x == MainStreetRoom.groceryApproachPosition.x && pos.y == MainStreetRoom.groceryApproachPosition.y {
            return "Ты как раз напротив продуктового. Если хочешь войти, иди вправо."
        }

        if pos.x >= MainStreetRoom.gatePosition.x - 2 &&
            pos.x <= MainStreetRoom.gatePosition.x + 2 &&
            pos.y >= MainStreetRoom.groceryApproachPosition.y - 8 &&
            pos.y <= MainStreetRoom.groceryApproachPosition.y + 8 {
            return "Ты почти напротив продуктового. Еще немного вперед, а потом иди вправо к магазину."
        }

        if pos.y > MainStreetRoom.groceryDoorPosition.y + 16 {
            return "Ты идешь по большой улице от калитки. Продуктовый дальше впереди справа."
        }

        return "Ты идешь по большой улице. Вокруг много пространства, а справа впереди уже чувствуется большой продуктовый."
    }
}
