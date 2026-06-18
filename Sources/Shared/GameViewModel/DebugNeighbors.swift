import Foundation

extension GameViewModel {
    func debugNeighborStateName() -> String {
        if neighborEncounterMachine.isResolved { return "resolved" }
        if neighborEncounterMachine.isBreakInActive { return "breakin" }
        if neighborEncounterMachine.isDoorbellRaised { return "doorbell" }
        if neighborEncounterMachine.isWarned { return "warned" }
        return "calm"
    }

    func debugSetNeighborState(arguments: [String: Any]) throws -> [String: Any] {
        guard let rawState = arguments["state"] as? String else {
            throw LiveGameBridgeError("Для neighbor_set_state нужен state.")
        }

        cancelNeighborTasks()
        switch rawState.lowercased() {
        case "calm":
            neighborEncounterMachine.resetToCalm()
        case "warn", "warned":
            neighborEncounterMachine.markWarned()
        case "doorbell":
            neighborEncounterMachine.markDoorbellRaised()
        case "breakin", "break_in":
            neighborEncounterMachine.markBreakInStarted()
        case "resolved":
            neighborEncounterMachine.markResolved()
        default:
            throw LiveGameBridgeError("Неизвестное состояние соседа: \(rawState)")
        }

        refreshScreenState()
        return debugRuntimeStatePayload(message: "Сосед переведен в состояние \(debugNeighborStateName()).")
    }

    func debugTriggerNeighborLoudStep() -> [String: Any] {
        let step = neighborEncounterMachine.resolveLoudAction()
        let result: String

        switch step {
        case .warn:
            result = "Сосед перешел в предупреждение."
        case .ringDoorbell:
            audioCoordinator.playEffect(.doorbellMain)
            scheduleNeighborResponse()
            result = "Сосед поднял дверной звонок."
        case .startBreakIn:
            startNeighborBreakIn(
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
            debugNeighborResponsePauseRange = min...max
        }

        if let min = arguments["breakInPauseMin"] as? Double,
           let max = arguments["breakInPauseMax"] as? Double,
           min > 0, max >= min {
            debugNeighborBreakInPauseRange = min...max
        }

        if let hits = arguments["hitsTarget"] as? Int {
            debugNeighborDoorHitsTargetOverride = max(1, hits)
        }

        if let count = arguments["footstepCount"] as? Int {
            debugNeighborFootstepCountOverride = max(0, count)
        }

        if let pause = arguments["footstepPause"] as? Double {
            debugNeighborFootstepPauseOverride = max(0, pause)
        }

        if (arguments["reset"] as? Bool) == true {
            debugNeighborResponsePauseRange = nil
            debugNeighborBreakInPauseRange = nil
            debugNeighborDoorHitsTargetOverride = nil
            debugNeighborFootstepCountOverride = nil
            debugNeighborFootstepPauseOverride = nil
        }

        return debugRuntimeStatePayload(message: "Отладочная конфигурация соседей обновлена.")
    }
}
