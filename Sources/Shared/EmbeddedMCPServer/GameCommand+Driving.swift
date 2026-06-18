import Foundation

extension GameCommand {
    var isMovement: Bool {
        switch self {
        case .moveForward, .moveBackward, .moveLeft, .moveRight:
            return true
        default:
            return false
        }
    }
}
