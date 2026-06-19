import Foundation
import GameplayKit

// MARK: - DoorLifecycleMachine

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

// MARK: - GateLifecycleMachine

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

// MARK: - DoorDelegate

@MainActor
protocol DoorDelegate: AnyObject {
    func addLog(_ line: String)
    func announce(_ text: String)
    func refreshScreenState()
    var audioCoordinator: AudioCoordinator { get }
    var currentRoom: RoomDefinition { get }
    var state: WorldRuntimeState { get }
    var currentTraversalMode: RoomMovementMode { get }
    func doorLinkID(for door: DoorDefinition) -> String
    func doorMachine(for door: DoorDefinition) -> DoorLifecycleMachine
}

// MARK: - DoorSystem

@MainActor
final class DoorSystem {
    weak var delegate: DoorDelegate?

    var doorLifecycleMachines: [String: DoorLifecycleMachine] = [:]
    var gateLifecycleMachines: [String: GateLifecycleMachine] = [:]
    var gateTransitionTasks: [String: Task<Void, Never>] = [:]

    // MARK: - Timed door configuration

    func timedDoorConfiguration(for door: DoorDefinition) -> TimedDoorTransitionConfiguration? {
        guard case let .timedGate(configuration) = door.interactionStyle else {
            return nil
        }
        return configuration
    }

    // MARK: - Gate machine

    func gateMachine(for door: DoorDefinition) -> GateLifecycleMachine {
        let linkID = delegate?.doorLinkID(for: door) ?? ""

        if let machine = gateLifecycleMachines[linkID] {
            return machine
        }

        let machine = GateLifecycleMachine()
        gateLifecycleMachines[linkID] = machine
        return machine
    }

    // MARK: - Cancel gate transitions

    func cancelGateTransitionTasks(resetMachines: Bool) {
        gateTransitionTasks.values.forEach { $0.cancel() }
        gateTransitionTasks.removeAll()

        if resetMachines {
            gateLifecycleMachines.removeAll()
        }
    }

    // MARK: - Door state queries

    func isDoorOpened(_ door: DoorDefinition) -> Bool {
        if timedDoorConfiguration(for: door) != nil {
            return gateMachine(for: door).isOpen
        }
        return delegate?.doorMachine(for: door).isOpen ?? false
    }

    func doorActionTitle(for door: DoorDefinition) -> String {
        if timedDoorConfiguration(for: door) != nil {
            let machine = gateMachine(for: door)
            if machine.isOpening {
                return "Открывается..."
            }
            if machine.isClosing {
                return "Закрывается..."
            }
            return machine.isOpen ? "Закрыть калитку" : "Открыть калитку"
        }

        let machine = delegate?.doorMachine(for: door)
        if machine?.isLocked == true {
            return "Проверить дверь"
        }
        return machine?.isOpen == true ? "Закрыть" : "Открыть"
    }

    func doorDescriptionStateText(for door: DoorDefinition) -> String {
        if timedDoorConfiguration(for: door) != nil {
            let machine = gateMachine(for: door)
            if machine.isOpening {
                return "Она открывается. Сначала дождись конца звука, потом уже проходи."
            }
            if machine.isClosing {
                return "Она закрывается. Пока идет звук, подожди немного."
            }
            if machine.isOpen {
                return "Она открыта. Нажми \(passCommandHint(for: door)), чтобы пройти, или действие, чтобы закрыть."
            }
            return "Она закрыта. Нажми действие, чтобы открыть."
        }

        if door.state == .locked {
            return "Она заперта."
        }

        if isDoorOpened(door) {
            return "Она открыта. Нажми \(passCommandHint(for: door)), чтобы пройти, или действие, чтобы закрыть."
        }

        return "Она закрыта. Нажми действие, чтобы открыть."
    }

    // MARK: - Timed door action

    func handleTimedDoorAction(_ door: DoorDefinition, configuration: TimedDoorTransitionConfiguration) {
        let machine = gateMachine(for: door)

        if machine.isOpening {
            delegate?.announce("Калитка уже открывается. Подожди немного.")
            return
        }

        if machine.isClosing {
            delegate?.announce("Калитка уже закрывается. Подожди немного.")
            return
        }

        if machine.isOpen {
            guard machine.beginClosing() else { return }
            delegate?.audioCoordinator.playEffect(configuration.closeCue)
            delegate?.addLog("Калитка закрывается: \(door.name)")
            delegate?.announce("Закрываешь \(doorAccusativeName(for: door)).")
            delegate?.refreshScreenState()
            scheduleTimedDoorCompletion(for: door, isOpening: false, duration: configuration.closeDuration)
            return
        }

        guard machine.beginOpening() else { return }
        delegate?.audioCoordinator.playEffect(configuration.openCue)
        delegate?.addLog("Калитка открывается: \(door.name)")
        delegate?.announce("Открываешь \(doorAccusativeName(for: door)). Подожди немного.")
        delegate?.refreshScreenState()
        scheduleTimedDoorCompletion(for: door, isOpening: true, duration: configuration.openDuration)
    }

    // MARK: - Schedule timed completion

    func scheduleTimedDoorCompletion(for door: DoorDefinition, isOpening: Bool, duration: TimeInterval) {
        let linkID = delegate?.doorLinkID(for: door) ?? ""
        gateTransitionTasks[linkID]?.cancel()

        gateTransitionTasks[linkID] = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(0, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self, !Task.isCancelled else { return }

            let machine = self.gateMachine(for: door)
            if isOpening {
                guard machine.finishOpening() else { return }
                self.delegate?.addLog("Калитка открыта: \(door.name)")
                self.delegate?.refreshScreenState()
                self.delegate?.announce("Калитка открыта. Теперь можно пройти.")
            } else {
                guard machine.finishClosing() else { return }
                self.delegate?.addLog("Калитка закрыта: \(door.name)")
                self.delegate?.refreshScreenState()
                self.delegate?.announce("Калитка закрыта.")
            }

            self.gateTransitionTasks[linkID] = nil
        }
    }

    // MARK: - Pass command hint

    func passCommandHint(for door: DoorDefinition) -> String {
        guard delegate?.currentTraversalMode == .freeGrid4Way else {
            return "вперед"
        }

        let position = delegate?.state.player.roomPosition
        let room = delegate?.currentRoom

        if position?.y == 0 {
            return "вперед"
        }
        if position?.y == (room?.height ?? 1) - 1 {
            return "назад"
        }
        if position?.x == 0 {
            return "влево"
        }
        if position?.x == (room?.width ?? 1) - 1 {
            return "вправо"
        }

        return "вперед"
    }

    // MARK: - Door accusative name

    func doorAccusativeName(for door: DoorDefinition) -> String {
        switch door.name {
        case "калитка":
            return "калитку"
        default:
            return door.name
        }
    }
}
