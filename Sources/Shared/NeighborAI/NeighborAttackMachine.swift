import Foundation
import GameplayKit

// MARK: - NeighborAttackMachine

/// Управляет последовательностью атаки соседа: Idle → Approaching → Striking → Muffled.
/// Muffled — игрок поражён, звуки становится приглушёнными.
@MainActor
final class NeighborAttackMachine {

    // MARK: - States

    private final class IdleState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ApproachingState.self
        }
    }

    private final class ApproachingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == StrikingState.self || stateClass == IdleState.self
        }
    }

    private final class StrikingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == MuffledState.self || stateClass == IdleState.self
        }
    }

    private final class MuffledState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == IdleState.self
        }
    }

    // MARK: - Properties

    private let machine: GKStateMachine

    weak var audioCoordinator: AudioCoordinator?

    // MARK: - Init

    init() {
        machine = GKStateMachine(states: [
            IdleState(),
            ApproachingState(),
            StrikingState(),
            MuffledState()
        ])
        machine.enter(IdleState.self)
    }

    // MARK: - State queries

    var isIdle: Bool { machine.currentState is IdleState }
    var isApproaching: Bool { machine.currentState is ApproachingState }
    var isStriking: Bool { machine.currentState is StrikingState }
    var isMuffled: Bool { machine.currentState is MuffledState }

    /// Текущее состояние машины для отладки / логирования.
    var currentStateLabel: String {
        switch machine.currentState {
        case is IdleState: return "idle"
        case is ApproachingState: return "approaching"
        case is StrikingState: return "striking"
        case is MuffledState: return "muffled"
        default: return "unknown"
        }
    }

    // MARK: - Transitions

    /// Сосед начинает приближаться к игроку.
    func beginApproach() {
        _ = machine.enter(ApproachingState.self)
    }

    /// Сосед наносит удар.
    func strike() {
        _ = machine.enter(StrikingState.self)
    }

    /// Применить приглушение звука (после удара).
    func applyMuffled() {
        _ = machine.enter(MuffledState.self)
        audioCoordinator?.isMuffled = true
    }

    /// Снять приглушение звука (игрок поднялся).
    func clearMuffled() {
        _ = machine.enter(IdleState.self)
        audioCoordinator?.isMuffled = false
    }

    /// Полный сброс в начальное состояние.
    func reset() {
        if isMuffled {
            audioCoordinator?.isMuffled = false
        }
        _ = machine.enter(IdleState.self)
    }
}
