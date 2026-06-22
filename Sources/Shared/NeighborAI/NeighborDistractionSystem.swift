import Foundation

@MainActor
final class NeighborDistractionSystem {
    private(set) var isDistracted: Bool = false
    private(set) var distractionPosition: GridPosition?
    private var distractionEndTime: Date?

    /// Can the player throw to distract?
    func isThrowValid(heldItem: HeldItem?) -> Bool {
        heldItem != nil
    }

    /// Start distraction - neighbor goes to investigate thrown item
    func distract(to position: GridPosition, duration: TimeInterval = 5.0) {
        isDistracted = true
        distractionPosition = position
        distractionEndTime = Date().addingTimeInterval(duration)
    }

    /// Check if distraction is still active
    func update() {
        guard isDistracted else { return }
        if let endTime = distractionEndTime, Date() >= endTime {
            clearDistraction()
        }
    }

    /// Clear distraction
    func clearDistraction() {
        isDistracted = false
        distractionPosition = nil
        distractionEndTime = nil
    }

    /// Reset to initial state
    func reset() {
        clearDistraction()
    }
}
