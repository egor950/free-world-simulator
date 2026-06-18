import Foundation

@MainActor
final class EmbeddedGameRuntime: MCPToolRuntime {
    private let bridge: LiveGameBridge
    private var lastCommandAt: Date = .distantPast
    private let movementInterval: TimeInterval = 0.46
    private let actionInterval: TimeInterval = 0.58
    private let describeInterval: TimeInterval = 0.68

    init(bridge: LiveGameBridge = .shared) {
        self.bridge = bridge
    }

    func launchLiveGame() throws -> [String: Any] {
        _ = bridge.makeViewModel()
        return [
            "mode": "embedded-live",
            "message": "Игра уже запущена и встроенный MCP готов принимать команды."
        ]
    }

    func continueGame() throws -> [String: Any] {
        try payload(from: bridge.performEmbeddedAction("continue_game", arguments: [:]))
    }

    func startGame(name: String, kind: String) throws -> [String: Any] {
        let result = try payload(from: bridge.performEmbeddedAction("start_game", arguments: [
            "name": name,
            "kind": kind
        ]))
        lastCommandAt = Date()
        return result
    }

    func press(_ commandName: String) throws -> [String: Any] {
        if let command = GameCommand.parse(commandName) {
            waitForCommandWindow(for: command)
        }
        let result = try payload(from: bridge.performEmbeddedAction("press", arguments: [
            "command": commandName
        ]))
        lastCommandAt = Date()
        return result
    }

    func keyDown(_ commandName: String) throws -> [String: Any] {
        let result = try payload(from: bridge.performEmbeddedAction("key_down", arguments: [
            "command": commandName
        ]))
        lastCommandAt = Date()
        return result
    }

    func keyUp(_ commandName: String) throws -> [String: Any] {
        let result = try payload(from: bridge.performEmbeddedAction("key_up", arguments: [
            "command": commandName
        ]))
        lastCommandAt = Date()
        return result
    }

    func holdKey(_ commandName: String, duration: TimeInterval) throws -> [String: Any] {
        let safeDuration = max(0.05, min(10.0, duration))
        _ = try keyDown(commandName)
        Thread.sleep(forTimeInterval: safeDuration)
        return try keyUp(commandName)
    }

    func getState() throws -> [String: Any] {
        try payload(from: bridge.performEmbeddedAction("get_state", arguments: [:]))
    }

    func observeGame(phraseCursor: Int, gameLogCursor: Int, bridgeLogCursor: Int) throws -> [String: Any] {
        try payload(from: bridge.performEmbeddedAction("observe_game", arguments: [
            "phraseCursor": max(0, phraseCursor),
            "gameLogCursor": max(0, gameLogCursor),
            "bridgeLogCursor": max(0, bridgeLogCursor)
        ]))
    }

    func getPhrases(limit: Int) throws -> [String] {
        try stringArrayPayload(from: bridge.performEmbeddedAction("get_phrases", arguments: [
            "limit": max(1, limit)
        ]))
    }

    func getLog(limit: Int) throws -> [String] {
        try stringArrayPayload(from: bridge.performEmbeddedAction("get_log", arguments: [
            "limit": max(1, limit)
        ]))
    }

    func listDebugScenarios() throws -> [[String: String]] {
        guard let payload = try bridge.performEmbeddedAction("list_debug_scenarios", arguments: [:]) as? [[String: String]] else {
            throw RuntimeError("Не удалось получить список отладочных сценариев.")
        }
        return payload
    }

    func runDebugScenario(_ name: String) throws -> [String: Any] {
        let result = try payload(from: bridge.performEmbeddedAction("run_debug_scenario", arguments: [
            "name": name
        ]))
        lastCommandAt = Date()
        return result
    }

    func teleport(roomID: String, x: Int, y: Int) throws -> [String: Any] {
        let result = try payload(from: bridge.performEmbeddedAction("teleport", arguments: [
            "roomID": roomID,
            "x": x,
            "y": y
        ]))
        lastCommandAt = Date()
        return result
    }

    func debugWorld(arguments: [String: Any]) throws -> [String: Any] {
        let result = try payload(from: bridge.performEmbeddedAction("debug_world", arguments: arguments))
        lastCommandAt = Date()
        return result
    }

    private func payload(from value: Any) throws -> [String: Any] {
        guard let payload = value as? [String: Any] else {
            throw RuntimeError("Игра вернула непонятное состояние.")
        }
        return payload
    }

    private func stringArrayPayload(from value: Any) throws -> [String] {
        guard let payload = value as? [String] else {
            throw RuntimeError("Игра вернула непонятный список.")
        }
        return payload
    }

    private func waitForCommandWindow(for command: GameCommand) {
        let elapsed = Date().timeIntervalSince(lastCommandAt)
        let requiredInterval = interval(for: command)
        if elapsed < requiredInterval {
            Thread.sleep(forTimeInterval: requiredInterval - elapsed)
        }
    }

    private func interval(for command: GameCommand) -> TimeInterval {
        if command.isMovement {
            return movementInterval
        }

        switch command {
        case .describeFocus:
            return describeInterval
        case .primaryAction, .forceAction, .throwObject, .placeHeldItem:
            return actionInterval
        default:
            return actionInterval
        }
    }
}
