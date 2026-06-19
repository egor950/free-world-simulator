import Foundation

extension GameViewModel {
    func timedDoorConfiguration(for door: DoorDefinition) -> TimedDoorTransitionConfiguration? {
        doors.timedDoorConfiguration(for: door)
    }

    func gateMachine(for door: DoorDefinition) -> GateLifecycleMachine {
        doors.gateMachine(for: door)
    }

    func cancelGateTransitionTasks(resetMachines: Bool) {
        doors.cancelGateTransitionTasks(resetMachines: resetMachines)
    }

    func isDoorOpened(_ door: DoorDefinition) -> Bool {
        doors.isDoorOpened(door)
    }

    func doorActionTitle(for door: DoorDefinition) -> String {
        doors.doorActionTitle(for: door)
    }

    func doorDescriptionStateText(for door: DoorDefinition) -> String {
        doors.doorDescriptionStateText(for: door)
    }

    func handleTimedDoorAction(_ door: DoorDefinition, configuration: TimedDoorTransitionConfiguration) {
        doors.handleTimedDoorAction(door, configuration: configuration)
    }

    func scheduleTimedDoorCompletion(for door: DoorDefinition, isOpening: Bool, duration: TimeInterval) {
        doors.scheduleTimedDoorCompletion(for: door, isOpening: isOpening, duration: duration)
    }

    func passCommandHint(for door: DoorDefinition) -> String {
        doors.passCommandHint(for: door)
    }

    func doorAccusativeName(for door: DoorDefinition) -> String {
        doors.doorAccusativeName(for: door)
    }
}
