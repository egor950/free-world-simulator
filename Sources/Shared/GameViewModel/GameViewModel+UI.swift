import Foundation

extension GameViewModel {
    var canFinishCharacterCreation: Bool {
        !ui.characterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var currentCharacterSummary: String {
        let safeName = ui.characterName.trimmingCharacters(in: .whitespacesAndNewlines)
        if safeName.isEmpty {
            return "Имя пока не введено"
        }
        return "\(ui.selectedCharacterKind.rawValue), \(safeName)"
    }

    var movementButtons: [PlatformButtonDefinition] {
        [
            PlatformButtonDefinition(command: .moveLeft, title: "Влево", hint: "Шаг влево"),
            PlatformButtonDefinition(command: .moveForward, title: "Идти", hint: "Шаг вперед"),
            PlatformButtonDefinition(command: .moveRight, title: "Вправо", hint: "Шаг вправо"),
            PlatformButtonDefinition(command: .moveBackward, title: "Назад", hint: "Шаг назад")
        ]
    }

    var actionButtons: [PlatformButtonDefinition] {
        if ui.isInventoryOpen {
            return inventoryButtons
        }

        var buttons: [PlatformButtonDefinition] = []

        if let action = currentFocusDoor {
            buttons.append(
                PlatformButtonDefinition(
                    command: .primaryAction,
                    title: doorActionTitle(for: action),
                    hint: "Действие у двери"
                )
            )
        } else if let action = action(for: .primary) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .primaryAction,
                    title: action.title,
                    hint: "Главное действие"
                )
            )
        }

        if let action = action(for: .force) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .forceAction,
                    title: action.title,
                    hint: "Силовое действие"
                )
            )
        }

        if let action = action(for: .throwItem) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .throwObject,
                    title: action.title,
                    hint: "Сбросить или оттолкнуть"
                )
            )
        }

        buttons.append(
            PlatformButtonDefinition(
                command: .describeFocus,
                title: "Описание",
                hint: "Полное описание"
            )
        )

        if let action = action(for: .placeHeldItem) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .placeHeldItem,
                    title: action.title,
                    hint: "Положить обратно"
                )
            )
        }

        if let quickAction = inventoryQuickAction() {
            buttons.append(
                PlatformButtonDefinition(
                    command: .inventoryQuickAction,
                    title: quickAction.title,
                    hint: "Быстрое действие с предметом"
                )
            )
        }

        if state.player.heldItem != nil {
            buttons.append(
                PlatformButtonDefinition(
                    command: .inventoryToggle,
                    title: "Инвентарь",
                    hint: "Открыть предмет в руках"
                )
            )
        }

        return buttons
    }

    var inventoryButtons: [PlatformButtonDefinition] {
        var buttons: [PlatformButtonDefinition] = []

        if let action = heldItemAction(for: .primary) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .primaryAction,
                    title: action.title,
                    hint: "E"
                )
            )
        }

        if let action = heldItemAction(for: .force) {
            buttons.append(
                PlatformButtonDefinition(
                    command: .forceAction,
                    title: action.title,
                    hint: "F"
                )
            )
        }

        if let action = inventoryQuickAction() {
            buttons.append(
                PlatformButtonDefinition(
                    command: .inventoryQuickAction,
                    title: action.title,
                    hint: "C"
                )
            )
        }

        buttons.append(
            PlatformButtonDefinition(
                command: .describeFocus,
                title: "Осмотреть",
                hint: "R"
            )
        )

        buttons.append(
            PlatformButtonDefinition(
                command: .inventoryToggle,
                title: "Закрыть",
                hint: "Escape"
            )
        )

        return buttons
    }

    var debugRoomPosition: GridPosition {
        state.player.roomPosition
    }
}
