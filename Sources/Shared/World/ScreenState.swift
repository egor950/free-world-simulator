import Foundation

extension GameViewModel {
    func refreshScreenState(syncAudio: Bool = true) {
        syncNavigationBeaconState()
        syncGameplayStateMachines()
        let nextRoomTitle = currentRoom.title
        if ui.roomTitle != nextRoomTitle {
            ui.roomTitle = nextRoomTitle
        }

        let nextFocusTitle = currentFocusNode?.title ?? "Свободное место"
        if ui.focusTitle != nextFocusTitle {
            ui.focusTitle = nextFocusTitle
        }

        let nextFocusShortText = currentShortPrompt()
        if ui.focusShortText != nextFocusShortText {
            ui.focusShortText = nextFocusShortText
        }

        if let controlledCar = state.controlledCar {
            let nextStatusText = controlledCarStatusText(controlledCar)
            if ui.statusText != nextStatusText {
                ui.statusText = nextStatusText
            }
        }
        updateInventoryState()

        let nextHoldText: String
        if let heldItem = state.player.heldItem {
            nextHoldText = "В руках: \(heldItem.name). \(state.player.pose.title.lowercased())."
        } else {
            nextHoldText = state.player.pose.title
        }
        if ui.holdText != nextHoldText {
            ui.holdText = nextHoldText
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
            if ui.inventoryTitle != "Инвентарь: \(heldItem.name)" {
                ui.inventoryTitle = "Инвентарь: \(heldItem.name)"
            }
            if ui.inventoryText != nextInventoryText {
                ui.inventoryText = nextInventoryText
            }
            return
        }

        if ui.inventoryTitle != "Инвентарь пуст" {
            ui.inventoryTitle = "Инвентарь пуст"
        }
        if ui.inventoryText != "Сейчас у тебя ничего нет в руках." {
            ui.inventoryText = "Сейчас у тебя ничего нет в руках."
        }
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
                if door.id == MainStreetRoom.groceryDoorID, navigationBeaconState.activeNavigationBeaconID == "grocery_store" {
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
}
