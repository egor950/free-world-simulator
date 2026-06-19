import GameplayKit

final class RoomTraversalMachine {
    private final class LinearTraversalState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == GridTraversalState.self
        }
    }

    private final class GridTraversalState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == LinearTraversalState.self
        }
    }

    private let machine = GKStateMachine(states: [
        LinearTraversalState(),
        GridTraversalState()
    ])

    init(initialMode: RoomMovementMode = .linearPath) {
        sync(mode: initialMode)
    }

    var isGridTraversal: Bool {
        machine.currentState is GridTraversalState
    }

    func sync(mode: RoomMovementMode) {
        switch mode {
        case .linearPath:
            _ = machine.enter(LinearTraversalState.self)
        case .freeGrid4Way:
            _ = machine.enter(GridTraversalState.self)
        }
    }
}

final class PoseMachine {
    private final class StandingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == LyingState.self || stateClass == CrawlingState.self
        }
    }

    private final class LyingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == StandingState.self || stateClass == CrawlingState.self
        }
    }

    private final class CrawlingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == StandingState.self || stateClass == LyingState.self
        }
    }

    private let machine = GKStateMachine(states: [
        StandingState(),
        LyingState(),
        CrawlingState()
    ])

    init(initialPose: PlayerPose = .standing) {
        sync(pose: initialPose)
    }

    var isStanding: Bool {
        machine.currentState is StandingState
    }

    var isLying: Bool {
        machine.currentState is LyingState
    }

    func sync(pose: PlayerPose) {
        switch pose {
        case .standing:
            _ = machine.enter(StandingState.self)
        case .lying:
            _ = machine.enter(LyingState.self)
        case .crawling:
            _ = machine.enter(CrawlingState.self)
        }
    }
}

final class InventoryMachine {
    private final class ClosedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == OpenState.self
        }
    }

    private final class OpenState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ClosedState.self
        }
    }

    private let machine = GKStateMachine(states: [
        ClosedState(),
        OpenState()
    ])

    init(isOpen: Bool = false) {
        sync(isOpen: isOpen)
    }

    var isOpen: Bool {
        machine.currentState is OpenState
    }

    func sync(isOpen: Bool) {
        if isOpen {
            _ = machine.enter(OpenState.self)
        } else {
            _ = machine.enter(ClosedState.self)
        }
    }

    @discardableResult
    func open() -> Bool {
        machine.enter(OpenState.self)
    }

    @discardableResult
    func close() -> Bool {
        machine.enter(ClosedState.self)
    }
}
