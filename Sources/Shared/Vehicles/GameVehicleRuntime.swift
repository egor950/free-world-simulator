import Foundation

@MainActor
final class GameVehicleRuntime {
    var carLifecycleTask: Task<Void, Never>?
    var drivingLoopTask: Task<Void, Never>?
    let carLifecycleMachine = CarLifecycleMachine()
    var streetCarSnapshots: [StreetTrafficCoordinator.StreetCarSnapshot] = []
    var isGasPressed = false
    var isBrakePressed = false
    var isLeftPressed = false
    var isRightPressed = false
    var driveElapsedTime: TimeInterval = 0
    var reverseHoldElapsed: TimeInterval = 0
    var gateAutoPassLockedZ: Float?
    var pendingDriveCommandResetTasks: [GameCommand: Task<Void, Never>] = [:]
    var drivingInputHeartbeat: [GameCommand: TimeInterval] = [:]
    var lastDrivingHintText: String = ""
    var lastDrivingHintAt: Date = .distantPast
}

extension GameViewModel {
    var carLifecycleTask: Task<Void, Never>? {
        get { vehicleRuntime.carLifecycleTask }
        set { vehicleRuntime.carLifecycleTask = newValue }
    }

    var drivingLoopTask: Task<Void, Never>? {
        get { vehicleRuntime.drivingLoopTask }
        set { vehicleRuntime.drivingLoopTask = newValue }
    }

    var carLifecycleMachine: CarLifecycleMachine {
        vehicleRuntime.carLifecycleMachine
    }

    var streetCarSnapshots: [StreetTrafficCoordinator.StreetCarSnapshot] {
        get { vehicleRuntime.streetCarSnapshots }
        set { vehicleRuntime.streetCarSnapshots = newValue }
    }

    var isGasPressed: Bool {
        get { vehicleRuntime.isGasPressed }
        set { vehicleRuntime.isGasPressed = newValue }
    }

    var isBrakePressed: Bool {
        get { vehicleRuntime.isBrakePressed }
        set { vehicleRuntime.isBrakePressed = newValue }
    }

    var isLeftPressed: Bool {
        get { vehicleRuntime.isLeftPressed }
        set { vehicleRuntime.isLeftPressed = newValue }
    }

    var isRightPressed: Bool {
        get { vehicleRuntime.isRightPressed }
        set { vehicleRuntime.isRightPressed = newValue }
    }

    var driveElapsedTime: TimeInterval {
        get { vehicleRuntime.driveElapsedTime }
        set { vehicleRuntime.driveElapsedTime = newValue }
    }

    var reverseHoldElapsed: TimeInterval {
        get { vehicleRuntime.reverseHoldElapsed }
        set { vehicleRuntime.reverseHoldElapsed = newValue }
    }

    var gateAutoPassLockedZ: Float? {
        get { vehicleRuntime.gateAutoPassLockedZ }
        set { vehicleRuntime.gateAutoPassLockedZ = newValue }
    }

    var pendingDriveCommandResetTasks: [GameCommand: Task<Void, Never>] {
        get { vehicleRuntime.pendingDriveCommandResetTasks }
        set { vehicleRuntime.pendingDriveCommandResetTasks = newValue }
    }

    var drivingInputHeartbeat: [GameCommand: TimeInterval] {
        get { vehicleRuntime.drivingInputHeartbeat }
        set { vehicleRuntime.drivingInputHeartbeat = newValue }
    }

    var lastDrivingHintText: String {
        get { vehicleRuntime.lastDrivingHintText }
        set { vehicleRuntime.lastDrivingHintText = newValue }
    }

    var lastDrivingHintAt: Date {
        get { vehicleRuntime.lastDrivingHintAt }
        set { vehicleRuntime.lastDrivingHintAt = newValue }
    }
}
