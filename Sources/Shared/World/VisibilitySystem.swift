import Foundation

extension GameViewModel {
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

        if itemID == GroceryStoreTeabag.itemID {
            return GroceryStoreTeabag.make()
        }

        if itemID == GroceryStoreSugar.itemID {
            return GroceryStoreSugar.make()
        }

        return nil
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
}
