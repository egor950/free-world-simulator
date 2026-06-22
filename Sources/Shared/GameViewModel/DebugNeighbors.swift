import Foundation

extension GameViewModel {
    func debugNeighborStateName() -> String {
        if neighbor.isResolved { return "resolved" }
        if neighbor.doorMachine.isBreaking { return "breakin" }
        if neighbor.isActive { return "active" }
        if neighbor.isWarned { return "warned" }
        return "calm"
    }

    func debugSetNeighborState(arguments: [String: Any]) throws -> [String: Any] {
        guard let rawState = arguments["state"] as? String else {
            throw LiveGameBridgeError("Для neighbor_set_state нужен state.")
        }

        neighbor.cancelNeighborTasks()
        switch rawState.lowercased() {
        case "calm":
            neighbor.resetNeighborEncounterState()
        case "warn", "warned":
            _ = neighbor.isWarned  // set to warned
            neighbor.simulateDoorbell()  // just enter warned state
        case "doorbell":
            neighbor.simulateDoorbell()
        case "breakin", "break_in":
            neighbor.doorMachine.beginBreaking()
        case "resolved":
            _ = neighbor.isResolved  // set resolved
        default:
            throw LiveGameBridgeError("Неизвестное состояние соседа: \(rawState)")
        }

        refreshScreenState()
        return debugRuntimeStatePayload(message: "Сосед переведен в состояние \(debugNeighborStateName()).")
    }

    func debugTriggerNeighborLoudStep() -> [String: Any] {
        let fakeAction = ItemAction(
            trigger: .primary,
            title: "Грохот",
            resultText: "Что-то сильно грохнуло.",
            sound: .cabinetSmash,
            requiresHeldItemID: nil,
            producesHeldItem: nil,
            stateMutation: { _ in }
        )

        let result: String
        if let line = neighbor.reactToLoudActionIfNeeded(for: fakeAction) {
            result = line
        } else {
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
