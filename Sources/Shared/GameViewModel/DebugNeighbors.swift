import Foundation

extension GameViewModel {
    func debugNeighborStateName() -> String {
        if neighbor.machine.isResolved { return "resolved" }
        if neighbor.machine.isBreakInActive { return "breakin" }
        if neighbor.machine.isDoorbellRaised { return "doorbell" }
        if neighbor.machine.isWarned { return "warned" }
        return "calm"
    }

    func debugSetNeighborState(arguments: [String: Any]) throws -> [String: Any] {
        guard let rawState = arguments["state"] as? String else {
            throw LiveGameBridgeError("Для neighbor_set_state нужен state.")
        }

        neighbor.cancelNeighborTasks()
        switch rawState.lowercased() {
        case "calm":
            neighbor.machine.resetToCalm()
        case "warn", "warned":
            neighbor.machine.markWarned()
        case "doorbell":
            neighbor.machine.markDoorbellRaised()
        case "breakin", "break_in":
            neighbor.machine.markBreakInStarted()
        case "resolved":
            neighbor.machine.markResolved()
        default:
            throw LiveGameBridgeError("Неизвестное состояние соседа: \(rawState)")
        }

        refreshScreenState()
        return debugRuntimeStatePayload(message: "Сосед переведен в состояние \(debugNeighborStateName()).")
    }

    func debugTriggerNeighborLoudStep() -> [String: Any] {
        let step = neighbor.machine.resolveLoudAction()
        let result: String

        switch step {
        case .warn:
            result = "Сосед перешел в предупреждение."
        case .ringDoorbell:
            audioCoordinator.playEffect(.doorbellMain)
            neighbor.scheduleNeighborResponse()
            result = "Сосед поднял дверной звонок."
        case .startBreakIn:
            neighbor.startNeighborBreakIn(
                introText: "Отладка. Сосед начинает ломать дверь.",
                finalText: "Отладка. Штурм уже запущен."
            )
            result = "Сосед начал штурм."
        case .intensifyBreakIn:
            audioCoordinator.playEffect(.doorBreakHeavy)
            result = "Сосед усилил штурм."
        case .ignore:
            result = "Сосед ничего не сделал."
        }

        refreshScreenState()
        return debugRuntimeStatePayload(message: result)
    }

    func debugSetNeighborConfig(arguments: [String: Any]) -> [String: Any] {
        if let min = arguments["responsePauseMin"] as? Double,
           let max = arguments["responsePauseMax"] as? Double,
           min > 0, max >= min {
            neighbor.debug.responsePauseRange = min...max
        }

        if let min = arguments["breakInPauseMin"] as? Double,
           let max = arguments["breakInPauseMax"] as? Double,
           min > 0, max >= min {
            neighbor.debug.breakInPauseRange = min...max
        }

        if let hits = arguments["hitsTarget"] as? Int {
            neighbor.debug.doorHitsTargetOverride = max(1, hits)
        }

        if let count = arguments["footstepCount"] as? Int {
            neighbor.debug.footstepCountOverride = max(0, count)
        }

        if let pause = arguments["footstepPause"] as? Double {
            neighbor.debug.footstepPauseOverride = max(0, pause)
        }

        if (arguments["reset"] as? Bool) == true {
            neighbor.debug.reset()
        }

        return debugRuntimeStatePayload(message: "Отладочная конфигурация соседей обновлена.")
    }
}
