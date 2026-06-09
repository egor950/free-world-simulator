import Foundation

extension GameViewModel {
    var streetCarInteractionDistance: Int { 2 }
    var currentTraversalMode: RoomMovementMode {
        roomTraversalMachine.isGridTraversal ? .freeGrid4Way : .linearPath
    }

    func syncGameplayStateMachines() {
        roomTraversalMachine.sync(mode: currentRoom.movementMode)
        poseMachine.sync(pose: state.player.pose)
        inventoryMachine.sync(isOpen: isInventoryOpen)
    }

    func setPlayerPose(_ pose: PlayerPose) {
        state.player.pose = pose
        poseMachine.sync(pose: pose)
    }

    func setInventoryOpen(_ isOpen: Bool) {
        self.isInventoryOpen = isOpen
        inventoryMachine.sync(isOpen: isOpen)
    }

    var currentRoom: RoomDefinition {
        rooms[state.player.roomID] ?? rooms[.hallway]!
    }

    var currentFocusNode: FocusNode? {
        if let controlledCar = state.controlledCar {
            return FocusNode(
                id: "controlled.car.\(controlledCar.id.uuidString)",
                title: controlledCar.title,
                position: state.player.roomPosition,
                target: .none,
                shortPrompt: controlledCarShortPrompt(controlledCar),
                fullDescription: controlledCarFullDescription(controlledCar)
            )
        }

        if let explicitNode = node(for: state.player.focusedTarget) {
            return explicitNode
        }

        if let exactNode = visibleNode(at: state.player.roomPosition) {
            return exactNode
        }

        if let ownedNode = nearbyOwnedParkedCarNode(maxDistance: streetCarInteractionDistance) {
            return ownedNode
        }

        return nearbyParkedStreetCarNode(maxDistance: streetCarInteractionDistance)
    }

    var currentFocusDoor: DoorDefinition? {
        guard let node = currentFocusNode, case let .door(id) = node.target else { return nil }
        return currentRoom.doors[id]
    }

    var currentFocusItem: ItemDefinition? {
        guard let node = currentFocusNode, case let .item(id) = node.target else { return nil }
        return itemDefinition(for: id)
    }

    var bedItemWhileOnBed: ItemDefinition? {
        guard !poseMachine.isStanding else { return nil }
        return currentRoom.items[BedroomBed.itemID]
    }

    var visibleNodes: [FocusNode] {
        (dynamicVisibleNodes + currentRoom.nodes).compactMap(adjustedNode)
    }

    var dynamicVisibleNodes: [FocusNode] {
        var nodes: [FocusNode] = []

        if currentRoom.id == .street {
            nodes.append(contentsOf: streetCarSnapshots.filter(\.isInspectable).map { snapshot in
                FocusNode(
                    id: "street.dynamic.car.\(snapshot.id.uuidString)",
                    title: snapshot.title,
                    position: snapshot.position,
                    target: .none,
                    shortPrompt: snapshot.shortPrompt,
                    fullDescription: snapshot.fullDescription
                )
            })
        }

        if currentRoom.id == .street || currentRoom.id == .mainStreet {
            let ownedCars = state.parkedOwnedCars.values
                .filter { $0.roomID == currentRoom.id }
                .sorted { lhs, rhs in
                    if lhs.gridPosition.y == rhs.gridPosition.y {
                        return lhs.gridPosition.x < rhs.gridPosition.x
                    }
                    return lhs.gridPosition.y < rhs.gridPosition.y
                }

            nodes.append(contentsOf: ownedCars.map { car in
                FocusNode(
                    id: "dynamic.ownedCar.\(car.id.uuidString)",
                    title: car.title,
                    position: car.gridPosition,
                    target: .none,
                    shortPrompt: parkedOwnedCarShortPrompt(car),
                    fullDescription: parkedOwnedCarFullDescription(car)
                )
            })
        }

        let relocatedItemIDs = state.locatedItemIDs.sorted()
        for itemID in relocatedItemIDs {
            guard state.room(for: itemID) == currentRoom.id,
                  currentRoom.items[itemID] == nil,
                  let definition = itemDefinition(for: itemID),
                  let position = state.position(for: itemID) else {
                continue
            }

            nodes.append(
                FocusNode(
                    id: "dynamic.item.\(itemID)",
                    title: definition.name,
                    position: position,
                    target: .item(itemID),
                    shortPrompt: definition.shortPromptProvider(state),
                    fullDescription: definition.fullDescriptionProvider(state)
                )
            )
        }

        return nodes
    }

    func itemDefinition(for itemID: String) -> ItemDefinition? {
        for room in rooms.values {
            if let item = room.items[itemID] {
                return item
            }
        }

        if KitchenMug.isMugItemID(itemID) {
            return KitchenMug.make(itemID: itemID)
        }

        return nil
    }

    func currentShortPrompt() -> String {
        if let controlledCar = state.controlledCar {
            return controlledCarShortPrompt(controlledCar)
        }

        if let driveableCar = currentFocusDriveableCarContext() {
            return driveableCarShortPrompt(driveableCar)
        }

        if let door = currentFocusDoor {
            if timedDoorConfiguration(for: door) != nil {
                let machine = gateMachine(for: door)
                if machine.isOpening {
                    return "\(door.shortPrompt) Калитка открывается."
                }
                if machine.isClosing {
                    return "\(door.shortPrompt) Калитка закрывается."
                }
                if machine.isOpen {
                    return "\(door.shortPrompt) Калитка открыта. Нажми \(passCommandHint(for: door)), чтобы пройти."
                }
                return "\(door.shortPrompt) Калитка закрыта."
            }

            if door.state == .locked {
                return "\(door.shortPrompt) Заперто."
            }
            if isDoorOpened(door) {
                let base = "\(door.shortPrompt) Дверь открыта. Нажми \(passCommandHint(for: door)), чтобы пройти."
                if door.id == MainStreetRoom.groceryDoorID, activeNavigationBeaconID == "grocery_store" {
                    return "\(base) Маяк довел тебя до входа."
                }
                return base
            }
            return "\(door.shortPrompt) Дверь закрыта."
        }

        if let item = currentFocusItem {
            return item.shortPromptProvider(state)
        }

        if currentRoom.id == .street,
           let nearbyCar = nearestParkedStreetCarSnapshot(maxDistance: streetCarInteractionDistance) {
            return nearbyCar.shortPrompt
        }

        if currentRoom.id == .street,
           let hint = nearestStreetCarGuidance(maxDistance: 6, includeDistance: true, parkedOnly: true) {
            return hint
        }

        if let hint = currentNavigationBeaconHint() {
            return "Маяк: \(hint)"
        }

        return currentFocusNode?.shortPrompt ?? ""
    }

    func refreshScreenState(syncAudio: Bool = true) {
        syncNavigationBeaconState()
        syncGameplayStateMachines()
        let nextRoomTitle = currentRoom.title
        if roomTitle != nextRoomTitle {
            roomTitle = nextRoomTitle
        }

        let nextFocusTitle = currentFocusNode?.title ?? "Свободное место"
        if focusTitle != nextFocusTitle {
            focusTitle = nextFocusTitle
        }

        let nextFocusShortText = currentShortPrompt()
        if focusShortText != nextFocusShortText {
            focusShortText = nextFocusShortText
        }

        if let controlledCar = state.controlledCar {
            let nextStatusText = controlledCarStatusText(controlledCar)
            if statusText != nextStatusText {
                statusText = nextStatusText
            }
        }
        updateInventoryState()

        let nextHoldText: String
        if let heldItem = state.player.heldItem {
            nextHoldText = "В руках: \(heldItem.name). \(state.player.pose.title.lowercased())."
        } else {
            nextHoldText = state.player.pose.title
        }
        if holdText != nextHoldText {
            holdText = nextHoldText
        }

        if syncAudio {
            syncAudioWorldState()
        }
    }

    func updateInventoryState() {
        if let heldItem = state.player.heldItem {
            var lines: [String] = []
            lines.append("E: \(heldItemAction(for: .primary)?.title ?? "Нет главного действия")")
            lines.append("F: \(heldItemAction(for: .force)?.title ?? "Нет силового действия")")
            lines.append("C: \(inventoryQuickAction()?.title ?? "Нет быстрого действия")")
            lines.append("R: Осмотреть предмет")
            lines.append("Escape: закрыть инвентарь")
            let nextInventoryText = lines.joined(separator: "\n")
            if inventoryTitle != "Инвентарь: \(heldItem.name)" {
                inventoryTitle = "Инвентарь: \(heldItem.name)"
            }
            if inventoryText != nextInventoryText {
                inventoryText = nextInventoryText
            }
            return
        }

        if inventoryTitle != "Инвентарь пуст" {
            inventoryTitle = "Инвентарь пуст"
        }
        if inventoryText != "Сейчас у тебя ничего нет в руках." {
            inventoryText = "Сейчас у тебя ничего нет в руках."
        }
    }

    func node(for target: FocusTarget) -> FocusNode? {
        switch target {
        case let .door(id):
            return visibleNodes.first { $0.target == .door(id) }
        case let .item(id):
            return visibleNodes.first { $0.target == .item(id) }
        case .none:
            return nil
        }
    }

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

    func nearestStreetCarGuidance(maxDistance: Int, includeDistance: Bool, parkedOnly: Bool = false) -> String? {
        guard currentRoom.id == .street, !streetCarSnapshots.isEmpty else {
            return nil
        }

        let candidates = parkedOnly ? streetCarSnapshots.filter(\.isParked) : streetCarSnapshots
        guard !candidates.isEmpty else {
            return nil
        }

        let playerPosition = state.player.roomPosition
        guard let nearest = candidates.min(by: {
            manhattanDistance(from: $0.position, to: playerPosition) <
            manhattanDistance(from: $1.position, to: playerPosition)
        }) else {
            return nil
        }

        let distance = manhattanDistance(from: nearest.position, to: playerPosition)
        guard distance > 0, distance <= maxDistance else {
            return nil
        }

        let dx = nearest.position.x - playerPosition.x
        let dy = nearest.position.y - playerPosition.y

        let horizontal: String
        if dx > 0 {
            horizontal = "правее"
        } else if dx < 0 {
            horizontal = "левее"
        } else {
            horizontal = "ровно по линии"
        }

        let vertical: String
        if dy < 0 {
            vertical = "впереди"
        } else if dy > 0 {
            vertical = "позади"
        } else {
            vertical = "на одном уровне"
        }

        if includeDistance {
            return "Ближайшая машина \(vertical), \(horizontal). До нее примерно \(distance) шагов."
        }

        return "Ближайшая машина \(vertical), \(horizontal)."
    }

    func normalizedFocusTarget(_ target: FocusTarget) -> FocusTarget {
        guard case let .item(id) = target else {
            return target
        }

        if id == BedroomPillow.itemID {
            if state.player.heldItem?.itemID == id {
                if !poseMachine.isStanding, currentRoom.items[BedroomBed.itemID] != nil {
                    return .item(BedroomBed.itemID)
                }
                return .none
            }

            if let pillowPosition = currentPositionForPillow(),
               state.player.roomPosition != pillowPosition {
                if !poseMachine.isStanding, currentRoom.items[BedroomBed.itemID] != nil {
                    return .item(BedroomBed.itemID)
                }
                return .none
            }
        }

        return target
    }

    func visibleNode(at position: GridPosition) -> FocusNode? {
        visibleNodes.first { $0.position == position }
    }

    func nearbyDoorNode(maxDistance: Int) -> FocusNode? {
        let playerPosition = state.player.roomPosition
        let doorNodes = visibleNodes.filter {
            if case .door = $0.target {
                return true
            }
            return false
        }

        guard let nearest = doorNodes.min(by: {
            manhattanDistance(from: $0.position, to: playerPosition) <
            manhattanDistance(from: $1.position, to: playerPosition)
        }) else {
            return nil
        }

        let distance = manhattanDistance(from: nearest.position, to: playerPosition)
        return distance <= maxDistance ? nearest : nil
    }

    func currentFocusStreetCarSnapshot() -> StreetTrafficCoordinator.StreetCarSnapshot? {
        guard state.controlledCar == nil else {
            return nil
        }

        guard let node = currentFocusNode,
              node.id.hasPrefix("street.dynamic.car.") else {
            return nearestParkedStreetCarSnapshot(maxDistance: streetCarInteractionDistance)
        }

        let rawID = String(node.id.dropFirst("street.dynamic.car.".count))
        guard let uuid = UUID(uuidString: rawID) else {
            return streetCarSnapshots.first { $0.position == node.position }
                ?? nearestParkedStreetCarSnapshot(maxDistance: streetCarInteractionDistance)
        }

        return streetCarSnapshots.first { $0.id == uuid }
            ?? nearestParkedStreetCarSnapshot(maxDistance: streetCarInteractionDistance)
    }

    func nearbyParkedStreetCarNode(maxDistance: Int) -> FocusNode? {
        guard state.controlledCar == nil else {
            return nil
        }

        guard let snapshot = nearestParkedStreetCarSnapshot(maxDistance: maxDistance) else {
            return nil
        }

        return FocusNode(
            id: "street.dynamic.car.\(snapshot.id.uuidString)",
            title: snapshot.title,
            position: snapshot.position,
            target: .none,
            shortPrompt: snapshot.shortPrompt,
            fullDescription: snapshot.fullDescription
        )
    }

    func nearestParkedStreetCarSnapshot(maxDistance: Int) -> StreetTrafficCoordinator.StreetCarSnapshot? {
        guard currentRoom.id == .street else {
            return nil
        }

        let playerPosition = state.player.roomPosition
        let parkedCars = streetCarSnapshots.filter(\.isInspectable)
        guard !parkedCars.isEmpty else {
            return nil
        }

        return parkedCars.min(by: {
            manhattanDistance(from: $0.position, to: playerPosition) <
            manhattanDistance(from: $1.position, to: playerPosition)
        }).flatMap { snapshot in
            let distance = manhattanDistance(from: snapshot.position, to: playerPosition)
            return distance <= maxDistance ? snapshot : nil
        }
    }

    func adjustedNode(_ node: FocusNode) -> FocusNode? {
        if case let .door(id) = node.target, id == HallwayRoom.neighborDoorID {
            return isNeighborDoorVisible ? node : nil
        }

        guard case let .item(id) = node.target else {
            return node
        }

        let customPosition: GridPosition?
        switch id {
        case BedroomPillow.itemID:
            customPosition = currentPositionForPillow()
        default:
            customPosition = currentPositionForVisibleItem(
                itemID: id,
                defaultPosition: node.position,
                hiddenWhenOnStove: id == KitchenKettle.itemID
            )
        }

        guard let customPosition else {
            return nil
        }

        return FocusNode(
            id: node.id,
            title: node.title,
            position: customPosition,
            target: node.target,
            shortPrompt: node.shortPrompt,
            fullDescription: node.fullDescription
        )
    }

    func currentPositionForPillow() -> GridPosition? {
        if BedroomPillow.placement(in: state) == .held {
            return nil
        }

        if state.room(for: BedroomPillow.itemID) != nil && state.room(for: BedroomPillow.itemID) != currentRoom.id {
            return nil
        }

        if let customPosition = state.position(for: BedroomPillow.itemID) {
            return customPosition
        }

        if BedroomPillow.placement(in: state) == .onFloor {
            return GridPosition(x: 4, y: 3)
        }

        return GridPosition(x: 4, y: 2)
    }

    func currentPositionForVisibleItem(
        itemID: String,
        defaultPosition: GridPosition,
        hiddenWhenOnStove: Bool = false
    ) -> GridPosition? {
        if state.player.heldItem?.itemID == itemID {
            return nil
        }

        if hiddenWhenOnStove && KitchenKettle.placement(in: state) == .onBase {
            return nil
        }

        if itemID == KitchenMug.itemID,
           currentRoom.id == .kitchen,
           KitchenMug.isKitchenMugTaken(in: state) {
            return nil
        }

        if state.room(for: itemID) != nil && state.room(for: itemID) != currentRoom.id {
            return nil
        }

        if let customPosition = state.position(for: itemID) {
            return customPosition
        }

        return defaultPosition
    }

    func manhattanDistance(from lhs: GridPosition, to rhs: GridPosition) -> Int {
        abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y)
    }

    func addLog(_ line: String) {
        eventLog.insert(line, at: 0)
        if eventLog.count > 12 {
            eventLog.removeLast()
        }
        onLogLine?(line)
    }

    var isNeighborDoorVisible: Bool {
        (neighborEncounterMachine.isDoorbellRaised || neighborEncounterMachine.isBreakInActive) &&
        !neighborEncounterMachine.isResolved
    }
}
