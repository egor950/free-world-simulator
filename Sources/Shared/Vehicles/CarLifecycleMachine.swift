import GameplayKit

final class CarLifecycleMachine {
    private final class OnFootState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == CarDoorOpeningForEnterState.self
        }
    }

    private final class CarDoorOpeningForEnterState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == EnteringVehicleState.self
        }
    }

    private final class EnteringVehicleState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == CarDoorClosingAfterEnterState.self
        }
    }

    private final class CarDoorClosingAfterEnterState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == EngineStartingState.self || stateClass == EngineIdleState.self
        }
    }

    private final class EngineStartingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == EngineIdleState.self
        }
    }

    private final class EngineIdleState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == EngineStartingState.self ||
            stateClass == DrivingState.self ||
            stateClass == ParkedState.self ||
            stateClass == CarDoorOpeningForExitState.self
        }
    }

    private final class DrivingState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ParkedState.self
        }
    }

    private final class ParkedState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == DrivingState.self || stateClass == CarDoorOpeningForExitState.self
        }
    }

    private final class CarDoorOpeningForExitState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == ExitingVehicleState.self
        }
    }

    private final class ExitingVehicleState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == CarDoorClosingAfterExitState.self
        }
    }

    private final class CarDoorClosingAfterExitState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == OnFootState.self
        }
    }

    private let machine = GKStateMachine(states: [
        OnFootState(),
        CarDoorOpeningForEnterState(),
        EnteringVehicleState(),
        CarDoorClosingAfterEnterState(),
        EngineStartingState(),
        EngineIdleState(),
        DrivingState(),
        ParkedState(),
        CarDoorOpeningForExitState(),
        ExitingVehicleState(),
        CarDoorClosingAfterExitState()
    ])

    init() {
        reset()
    }

    var isOnFoot: Bool { machine.currentState is OnFootState }
    var isBusyWithDoorOrEngine: Bool {
        machine.currentState is CarDoorOpeningForEnterState ||
        machine.currentState is EnteringVehicleState ||
        machine.currentState is CarDoorClosingAfterEnterState ||
        machine.currentState is EngineStartingState ||
        machine.currentState is CarDoorOpeningForExitState ||
        machine.currentState is ExitingVehicleState ||
        machine.currentState is CarDoorClosingAfterExitState
    }
    var isDriving: Bool { machine.currentState is DrivingState }
    var isParked: Bool { machine.currentState is ParkedState }
    var isInsideVehicle: Bool {
        !isOnFoot &&
        !(machine.currentState is CarDoorOpeningForExitState) &&
        !(machine.currentState is ExitingVehicleState) &&
        !(machine.currentState is CarDoorClosingAfterExitState)
    }

    func reset() {
        _ = machine.enter(OnFootState.self)
    }

    @discardableResult func beginEnterOpening() -> Bool { machine.enter(CarDoorOpeningForEnterState.self) }
    @discardableResult func beginEntering() -> Bool { machine.enter(EnteringVehicleState.self) }
    @discardableResult func beginEnterClosing() -> Bool { machine.enter(CarDoorClosingAfterEnterState.self) }
    @discardableResult func beginEngineStarting() -> Bool { machine.enter(EngineStartingState.self) }
    @discardableResult func finishEnterToIdle() -> Bool { machine.enter(EngineIdleState.self) }
    @discardableResult func startDriving() -> Bool { machine.enter(DrivingState.self) }
    @discardableResult func park() -> Bool { machine.enter(ParkedState.self) }
    @discardableResult func beginExitOpening() -> Bool { machine.enter(CarDoorOpeningForExitState.self) }
    @discardableResult func beginExiting() -> Bool { machine.enter(ExitingVehicleState.self) }
    @discardableResult func beginExitClosing() -> Bool { machine.enter(CarDoorClosingAfterExitState.self) }
    @discardableResult func finishExit() -> Bool { machine.enter(OnFootState.self) }
}
