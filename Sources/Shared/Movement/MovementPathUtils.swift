import Foundation

extension GameViewModel {
    func linearTrackLength() -> Int {
        max(1, currentRoom.width * currentRoom.height)
    }

    func linearIndex(for position: GridPosition) -> Int {
        let x = min(max(0, position.x), currentRoom.width - 1)
        let y = min(max(0, position.y), currentRoom.height - 1)
        return y * currentRoom.width + x
    }

    func position(forWrappedLinearIndex index: Int) -> GridPosition {
        let length = linearTrackLength()
        let normalized = ((index % length) + length) % length
        let x = normalized % currentRoom.width
        let y = normalized / currentRoom.width
        return GridPosition(x: x, y: y)
    }

    func position(forClampedLinearIndex index: Int) -> GridPosition {
        let length = linearTrackLength()
        let normalized = min(max(0, index), length - 1)
        let x = normalized % currentRoom.width
        let y = normalized / currentRoom.width
        return GridPosition(x: x, y: y)
    }
}
