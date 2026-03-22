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
        if let explicitNode = node(for: state.player.focusedTarget) {
            return explicitNode
        }

        if let exactNode = visibleNode(at: state.player.roomPosition) {
            return exactNode
        }

        return nearbyParkedStreetCarNode(maxDistance: streetCarInteractionDistance)
    }

    var currentFocusDoor: DoorDefinition? {
        guard let node = currentFocusNode, case let .door(id) = node.target else { return nil }
        return currentRoom.doors[id]
    }

    var currentFocusItem: ItemDefinition? {
        guard let node = currentFocusNode, case let .item(id) = node.target else { return nil }
        return currentRoom.items[id]
    }

    var bedItemWhileOnBed: ItemDefinition? {
        guard !poseMachine.isStanding else { return nil }
        return currentRoom.items[BedroomBed.itemID]
    }

    var visibleNodes: [FocusNode] {
        (dynamicVisibleNodes + currentRoom.nodes).compactMap(adjustedNode)
    }

    var dynamicVisibleNodes: [FocusNode] {
        guard currentRoom.id == .street else {
            return []
        }

        return streetCarSnapshots.filter(\.isInspectable).map { snapshot in
            FocusNode(
                id: "street.dynamic.car.\(snapshot.id.uuidString)",
                title: snapshot.title,
                position: snapshot.position,
                target: .none,
                shortPrompt: snapshot.shortPrompt,
                fullDescription: snapshot.fullDescription
            )
        }
    }

    func currentShortPrompt() -> String {
        if let door = currentFocusDoor {
            if door.state == .locked {
                return "\(door.shortPrompt) Заперто."
            }
            if isDoorOpened(door) {
                return "\(door.shortPrompt) Дверь открыта. Нажми вперед, чтобы пройти."
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

        return currentFocusNode?.shortPrompt ?? ""
    }

    func refreshScreenState() {
        syncGameplayStateMachines()
        roomTitle = currentRoom.title
        focusTitle = currentFocusNode?.title ?? "Свободное место"
        focusShortText = currentShortPrompt()
        updateInventoryState()

        if let heldItem = state.player.heldItem {
            holdText = "В руках: \(heldItem.name). \(state.player.pose.title.lowercased())."
        } else {
            holdText = state.player.pose.title
        }

        syncAudioWorldState()
    }

    func updateInventoryState() {
        if let heldItem = state.player.heldItem {
            inventoryTitle = "Инвентарь: \(heldItem.name)"

            var lines: [String] = []
            lines.append("E: \(heldItemAction(for: .primary)?.title ?? "Нет главного действия")")
            lines.append("F: \(heldItemAction(for: .force)?.title ?? "Нет силового действия")")
            lines.append("C: \(inventoryQuickAction()?.title ?? "Нет быстрого действия")")
            lines.append("R: Осмотреть предмет")
            lines.append("Escape: закрыть инвентарь")
            inventoryText = lines.joined(separator: "\n")
            return
        }

        inventoryTitle = "Инвентарь пуст"
        inventoryText = "Сейчас у тебя ничего нет в руках."
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
        if currentRoom.id == .street {
            return streetEmptyDescription()
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
            return "Ты во дворе на асфальте. Совсем рядом машина, к ней можно подойти еще ближе."
        }

        if let hint = nearestStreetCarGuidance(maxDistance: 8, includeDistance: true, parkedOnly: true) {
            return "Ты во дворе на открытом асфальте. \(hint)"
        }

        return "Ты во дворе на открытом асфальте. Здесь можно свободно идти вверх, вниз, влево и вправо."
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

    func currentFocusStreetCarSnapshot() -> StreetTrafficCoordinator.StreetCarSnapshot? {
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

        guard case let .item(id) = node.target, id == BedroomPillow.itemID else {
            return node
        }

        guard let pillowPosition = currentPositionForPillow() else {
            return nil
        }

        return FocusNode(
            id: node.id,
            title: node.title,
            position: pillowPosition,
            target: node.target,
            shortPrompt: node.shortPrompt,
            fullDescription: node.fullDescription
        )
    }

    func currentPositionForPillow() -> GridPosition? {
        if state.player.heldItem?.itemID == BedroomPillow.itemID {
            return nil
        }

        if state.room(for: BedroomPillow.itemID) != nil && state.room(for: BedroomPillow.itemID) != currentRoom.id {
            return nil
        }

        if let customPosition = state.position(for: BedroomPillow.itemID) {
            return customPosition
        }

        if state.flag(itemID: BedroomPillow.itemID, key: BedroomPillow.onFloorFlag) {
            return GridPosition(x: 4, y: 3)
        }

        return GridPosition(x: 4, y: 2)
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
        state.flag(itemID: NeighborNoise.worldID, key: NeighborNoise.doorbellFlag) &&
        !state.flag(itemID: NeighborNoise.worldID, key: NeighborNoise.resolvedFlag)
    }
}
