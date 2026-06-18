import Foundation

extension GameViewModel {
    func moveFreely(_ command: GameCommand) {
        guard let delta = movementDelta(for: command) else {
            return
        }

        let nextPosition = GridPosition(
            x: state.player.roomPosition.x + delta.x,
            y: state.player.roomPosition.y + delta.y
        )

        guard nextPosition.x >= 0,
              nextPosition.y >= 0,
              nextPosition.x < currentRoom.width,
              nextPosition.y < currentRoom.height else {
            audioCoordinator.playBlockedMovement()
            announce(blockedText(for: command))
            return
        }

        let focusTarget = visibleNode(at: nextPosition)?.target ?? .none
        completeMovement(to: nextPosition, focusTarget: focusTarget)

        if let node = visibleNode(at: nextPosition) {
            addLog("Рядом: \(node.title)")
            announceMovementNode(node)
        } else if currentRoom.id == .street {
            if let hint = nearestStreetCarGuidance(maxDistance: 6, includeDistance: true, parkedOnly: true) {
                setSilentStatus("Ты идешь по асфальту. \(hint)")
            } else {
                setSilentStatus("Ты идешь по асфальту.")
            }
        } else if currentRoom.id == .mainStreet {
            setSilentStatus("Ты идешь по асфальту.")
        } else {
            setSilentStatus("Ты двигаешься дальше.")
        }
    }

    func movementDelta(for command: GameCommand) -> GridPosition? {
        switch command {
        case .moveForward:
            return GridPosition(x: 0, y: -1)
        case .moveBackward:
            return GridPosition(x: 0, y: 1)
        case .moveLeft:
            return GridPosition(x: -1, y: 0)
        case .moveRight:
            return GridPosition(x: 1, y: 0)
        default:
            return nil
        }
    }

    func blockedText(for command: GameCommand) -> String {
        if currentTraversalMode == .freeGrid4Way {
        switch command {
        case .moveForward:
            switch currentRoom.id {
            case .street:
                return "Дальше только калитка и край дороги."
            case .mainStreet:
                return "Дальше пока только край широкой улицы."
            default:
                return "Дальше хода нет."
            }
        case .moveBackward:
            switch currentRoom.id {
            case .street:
                return "Дальше уже стена дома и дверь позади."
            case .mainStreet:
                return "Позади только калитка и край улицы."
            default:
                return "Дальше хода нет."
            }
        case .moveLeft:
            switch currentRoom.id {
            case .street:
                return "Слева дальше уже стена дома."
            case .mainStreet:
                return "Слева дальше уже край улицы."
            default:
                return "Дальше хода нет."
            }
        case .moveRight:
            switch currentRoom.id {
            case .street:
                return "Справа дальше уже край двора."
            case .mainStreet:
                if state.player.roomPosition.x == currentRoom.width - 1 {
                    let storefrontBandStart = MainStreetRoom.groceryFacadeNorth.y - 4
                    let storefrontBandEnd = MainStreetRoom.groceryFacadeSouth.y + 4
                    if storefrontBandStart...storefrontBandEnd ~= state.player.roomPosition.y {
                        let dy = MainStreetRoom.groceryDoorPosition.y - state.player.roomPosition.y
                        if MainStreetRoom.groceryDoorPositions.contains(state.player.roomPosition) {
                            return "Справа вход в продуктовый. Открой дверь и нажми вправо, чтобы войти."
                        }
                        if dy < 0 {
                            return "Справа стена продуктового. Дверь чуть впереди вдоль фасада."
                        }
                        return "Справа стена продуктового. Дверь чуть позади вдоль фасада."
                    }
                }
                return "Справа дальше уже край улицы."
            default:
                return "Дальше хода нет."
            }
        default:
            return "Дальше хода нет."
        }
        }

        switch command {
        case .moveForward:
            return "Дальше по комнате пути нет."
        case .moveBackward:
            return "Назад дальше пути нет."
        case .moveLeft:
            return "Назад дальше пути нет."
        case .moveRight:
            return "Дальше по комнате пути нет."
        default:
            return "Дальше стена."
        }
    }
}
