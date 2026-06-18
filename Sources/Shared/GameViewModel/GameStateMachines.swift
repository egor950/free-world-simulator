import GameplayKit

final class DoorLifecycleMachine {
    private final class LockedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            false
        }
    }

    private final class ClosedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == OpenState.self || stateClass == LockedState.self
        }
    }

    private final class OpenState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ClosedState.self || stateClass == LockedState.self
        }
    }

    private let machine: GKStateMachine

    init(staticState: DoorState) {
        machine = GKStateMachine(states: [
            LockedState(),
            ClosedState(),
            OpenState()
        ])
        sync(staticState: staticState)
    }

    var isLocked: Bool {
        machine.currentState is LockedState
    }

    var isOpen: Bool {
        machine.currentState is OpenState
    }

    func sync(staticState: DoorState) {
        switch staticState {
        case .locked:
            _ = machine.enter(LockedState.self)
        case .closed:
            if machine.currentState == nil {
                _ = machine.enter(ClosedState.self)
            }
        }
    }

    @discardableResult
    func open() -> Bool {
        guard !isLocked else { return false }
        return machine.enter(OpenState.self)
    }

    @discardableResult
    func close() -> Bool {
        guard !isLocked else { return false }
        return machine.enter(ClosedState.self)
    }
}

final class GateLifecycleMachine {
    private final class ClosedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == OpeningState.self
        }
    }

    private final class OpeningState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == OpenState.self
        }
    }

    private final class OpenState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ClosingState.self
        }
    }

    private final class ClosingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ClosedState.self
        }
    }

    private let machine = GKStateMachine(states: [
        ClosedState(),
        OpeningState(),
        OpenState(),
        ClosingState()
    ])

    init() {
        _ = machine.enter(ClosedState.self)
    }

    var isOpen: Bool {
        machine.currentState is OpenState
    }

    var isOpening: Bool {
        machine.currentState is OpeningState
    }

    var isClosing: Bool {
        machine.currentState is ClosingState
    }

    func reset() {
        _ = machine.enter(ClosedState.self)
    }

    @discardableResult
    func beginOpening() -> Bool {
        machine.enter(OpeningState.self)
    }

    @discardableResult
    func finishOpening() -> Bool {
        machine.enter(OpenState.self)
    }

    @discardableResult
    func beginClosing() -> Bool {
        machine.enter(ClosingState.self)
    }

    @discardableResult
    func finishClosing() -> Bool {
        machine.enter(ClosedState.self)
    }
}

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
