import Foundation
import GameplayKit

// MARK: - NeighborChaseMachine

/// Управляет погоней соседа за игроком на улице.
///
/// Сценарий:
/// 1. Idle → Chasing — сосед замечает игрока на улице
/// 2. Chasing → LostPlayer — игрок слишком далеко
/// 3. LostPlayer → Chasing — сосед снова видит цель
/// 4. LostPlayer → Returning — сосед сдаётся
/// 5. Returning → Idle — сосед вернулся на позицию
final class NeighborChaseMachine {

    // MARK: - States

    private final class IdleState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ChasingState.self
        }
    }

    private final class ChasingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == LostPlayerState.self
                || stateClass == ReturningState.self
                || stateClass == IdleState.self
                || stateClass == PushingState.self
        }
    }

    private final class LostPlayerState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ChasingState.self
                || stateClass == ReturningState.self
                || stateClass == IdleState.self
        }
    }

    private final class ReturningState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == IdleState.self
        }
    }

    private final class PushingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == IdleState.self
        }
    }

    // MARK: - Machine

    private let machine: GKStateMachine

    init() {
        machine = GKStateMachine(states: [
            IdleState(),
            ChasingState(),
            LostPlayerState(),
            ReturningState(),
            PushingState()
        ])
        machine.enter(IdleState.self)
    }

    // MARK: - Queries

    var isIdle: Bool { machine.currentState is IdleState }
    var isChasing: Bool { machine.currentState is ChasingState }
    var isLost: Bool { machine.currentState is LostPlayerState }
    var isReturning: Bool { machine.currentState is ReturningState }
    var isPushing: Bool { machine.currentState is PushingState }

    var currentStateLabel: String {
        if isIdle { return "idle" }
        if isChasing { return "chasing" }
        if isLost { return "lost" }
        if isReturning { return "returning" }
        if isPushing { return "pushing" }
        return "unknown"
    }

    // MARK: - Transitions

    /// Сосед замечает игрока и начинает погоню.
    @discardableResult
    func beginChase() -> Bool {
        machine.enter(ChasingState.self)
    }

    /// Игрок слишком далеко — сосед теряет цель.
    @discardableResult
    func playerLost() -> Bool {
        machine.enter(LostPlayerState.self)
    }

    /// Сосед снова видит цель — возобновляет погоню.
    @discardableResult
    func reacquireTarget() -> Bool {
        machine.enter(ChasingState.self)
    }

    /// Сосед сдаётся и возвращается на позицию.
    @discardableResult
    func giveUpChase() -> Bool {
        machine.enter(ReturningState.self)
    }

    /// Сосед вернулся на исходную позицию.
    @discardableResult
    func returnedHome() -> Bool {
        machine.enter(IdleState.self)
    }

    /// Принудительный сброс в Idle.
    func reset() {
        _ = machine.enter(IdleState.self)
    }

    /// Сосед толкает игрока на улице.
    @discardableResult
    func beginPush() -> Bool {
        machine.enter(PushingState.self)
    }

    /// Толчок завершён, возврат в Idle.
    @discardableResult
    func endPush() -> Bool {
        machine.enter(IdleState.self)
    }
}
