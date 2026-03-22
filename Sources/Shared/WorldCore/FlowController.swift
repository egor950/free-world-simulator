import GameplayKit

final class GameFlowController {
    private let stateMachine: GKStateMachine

    init() {
        stateMachine = GKStateMachine(states: [
            WelcomeState(),
            CharacterCreationState(),
            ExplorationState(),
            FinishedState()
        ])
        stateMachine.enter(WelcomeState.self)
    }

    var currentStage: GameStage {
        switch stateMachine.currentState {
        case is WelcomeState:
            return .welcome
        case is CharacterCreationState:
            return .characterCreation
        case is FinishedState:
            return .finished
        default:
            return .exploration
        }
    }

    func enter(_ stage: GameStage) {
        switch stage {
        case .welcome:
            stateMachine.enter(WelcomeState.self)
        case .characterCreation:
            stateMachine.enter(CharacterCreationState.self)
        case .exploration:
            stateMachine.enter(ExplorationState.self)
        case .finished:
            stateMachine.enter(FinishedState.self)
        }
    }
}

private final class WelcomeState: GKState {}
private final class CharacterCreationState: GKState {}
private final class ExplorationState: GKState {}
private final class FinishedState: GKState {}
