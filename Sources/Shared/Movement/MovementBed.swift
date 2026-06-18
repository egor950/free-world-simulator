import Foundation

extension GameViewModel {
    func linearStep(for command: GameCommand) -> Int? {
        switch command {
        case .moveForward:
            return 1
        case .moveBackward:
            return -1
        case .moveLeft:
            return -1
        case .moveRight:
            return 1
        default:
            return nil
        }
    }

    func moveAlongBed(step: Int) {
        let anchor = bedAnchorPosition ?? state.player.roomPosition
        bedAnchorPosition = anchor
        let trackLength = linearTrackLength()
        let anchorIndex = linearIndex(for: anchor)
        let currentIndex = linearIndex(for: state.player.roomPosition)
        let minIndex = max(0, anchorIndex - 1)
        let maxIndex = min(trackLength - 1, anchorIndex + 1)
        let nextIndex = currentIndex + step

        guard nextIndex >= minIndex && nextIndex <= maxIndex else {
            audioCoordinator.playBlockedMovement()
            announce("Край кровати. Дальше нельзя, можно упасть.")
            return
        }

        let nextPosition = position(forClampedLinearIndex: nextIndex)
        let focusTarget = visibleNode(at: nextPosition)?.target ?? .none
        completeMovement(to: nextPosition, focusTarget: focusTarget)

        if let node = visibleNode(at: nextPosition) {
            addLog("Рядом: \(node.title)")
            announceMovementNode(node)
        } else {
            setSilentStatus("Ты подтягиваешься по кровати.")
        }
    }

    func syncBedAnchorAfterAction() {
        if poseMachine.isStanding {
            bedAnchorPosition = nil
            return
        }

        if let focusedItem = currentFocusItem, focusedItem.id == BedroomBed.itemID {
            bedAnchorPosition = state.player.roomPosition
        } else if bedAnchorPosition == nil {
            bedAnchorPosition = state.player.roomPosition
        }

        state.player.focusedTarget = normalizedFocusTarget(state.player.focusedTarget)
    }
}
