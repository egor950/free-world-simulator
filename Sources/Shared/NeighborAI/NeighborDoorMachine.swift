import GameplayKit

// MARK: - NeighborDoorMachine

/// State machine for neighbor door interaction:
/// Idle → Knocking → Waiting → Breaking → DoorBroken
final class NeighborDoorMachine {
    private final class IdleState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == KnockingState.self
        }
    }

    private final class KnockingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == WaitingState.self || stateClass == IdleState.self
        }
    }

    private final class WaitingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == KnockingState.self || stateClass == BreakingState.self || stateClass == IdleState.self
        }
    }

    private final class BreakingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == DoorBrokenState.self || stateClass == IdleState.self
        }
    }

    private final class DoorBrokenState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == IdleState.self
        }
    }

    private let machine: GKStateMachine

    init() {
        machine = GKStateMachine(states: [
            IdleState(),
            KnockingState(),
            WaitingState(),
            BreakingState(),
            DoorBrokenState()
        ])
        _ = machine.enter(IdleState.self)
    }

    // MARK: - State queries

    var isIdle: Bool { machine.currentState is IdleState }
    var isKnocking: Bool { machine.currentState is KnockingState }
    var isWaiting: Bool { machine.currentState is WaitingState }
    var isBreaking: Bool { machine.currentState is BreakingState }
    var isDoorBroken: Bool { machine.currentState is DoorBrokenState }

    // MARK: - Transitions

    @discardableResult
    func beginKnocking() -> Bool {
        machine.enter(KnockingState.self)
    }

    @discardableResult
    func pauseAfterKnocks() -> Bool {
        machine.enter(WaitingState.self)
    }

    @discardableResult
    func repeatKnocks() -> Bool {
        machine.enter(KnockingState.self)
    }

    @discardableResult
    func beginBreaking() -> Bool {
        machine.enter(BreakingState.self)
    }

    @discardableResult
    func doorDestroyed() -> Bool {
        machine.enter(DoorBrokenState.self)
    }

    func reset() {
        _ = machine.enter(IdleState.self)
    }
}
