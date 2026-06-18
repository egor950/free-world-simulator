import Foundation

extension GameViewModel {
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
}
