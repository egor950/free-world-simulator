import Foundation

struct RuntimeError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

@MainActor
final class GameRuntime {
    private var actionLog: [String] = []
    private var hasActiveSession = false
    private var lastLiveCommandAt: Date = .distantPast
    private let liveClient: LiveGameBridgeClient
    private let liveAppPath: String?
    private let liveMovementInterval: TimeInterval = 0.46
    private let liveActionInterval: TimeInterval = 0.58
    private let liveDescribeInterval: TimeInterval = 0.68

    init() {
        let env = ProcessInfo.processInfo.environment
        let bridgeHost = env["FREEWORLD_LIVE_HOST"] ?? LiveGameBridgeDefaults.host
        let bridgePort = UInt16(env["FREEWORLD_LIVE_PORT"] ?? "") ?? LiveGameBridgeDefaults.port
        liveClient = LiveGameBridgeClient(host: bridgeHost, port: bridgePort)
        liveAppPath = env["FREEWORLD_LIVE_APP_PATH"]
    }

    func launchLiveGame() throws -> [String: Any] {
        try ensureLiveGameAvailable()
        appendLog("attach_live_game")
        return [
            "mode": "live",
            "message": "Обычная игра запущена и готова принимать команды."
        ]
    }

    func continueGame() throws -> [String: Any] {
        try ensureLiveGameAvailable()
        let response = try liveClient.request(action: "get_state", arguments: [:])
        hasActiveSession = true
        lastLiveCommandAt = Date()
        appendLog("continue_game")
        return try payload(from: response)
    }

    func startGame(name: String, kind: String) throws -> [String: Any] {
        try ensureLiveGameAvailable()
        let response = try liveClient.request(action: "start_game", arguments: [
            "name": name,
            "kind": kind
        ])
        hasActiveSession = true
        lastLiveCommandAt = Date()
        appendLog("start_game live: \(name), \(kind)")
        return try payload(from: response)
    }

    func press(_ commandName: String) throws -> [String: Any] {
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        if let command = GameCommand.parse(commandName) {
            waitForLiveCommandWindow(for: command)
        }
        let response = try liveClient.request(action: "press", arguments: [
            "command": commandName
        ])
        lastLiveCommandAt = Date()
        appendLog("press live: \(commandName)")
        return try payload(from: response)
    }

    func keyDown(_ commandName: String) throws -> [String: Any] {
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        let response = try liveClient.request(action: "key_down", arguments: [
            "command": commandName
        ])
        lastLiveCommandAt = Date()
        appendLog("key_down live: \(commandName)")
        return try payload(from: response)
    }

    func keyUp(_ commandName: String) throws -> [String: Any] {
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        let response = try liveClient.request(action: "key_up", arguments: [
            "command": commandName
        ])
        lastLiveCommandAt = Date()
        appendLog("key_up live: \(commandName)")
        return try payload(from: response)
    }

    func holdKey(_ commandName: String, duration: TimeInterval) throws -> [String: Any] {
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        let safeDuration = max(0.05, min(10.0, duration))
        _ = try keyDown(commandName)
        Thread.sleep(forTimeInterval: safeDuration)
        return try keyUp(commandName)
    }

    func getState() throws -> [String: Any] {
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        let response = try liveClient.request(action: "get_state", arguments: [:])
        return try payload(from: response)
    }

    func observeGame(
        phraseCursor: Int,
        gameLogCursor: Int,
        bridgeLogCursor: Int
    ) throws -> [String: Any] {
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        let response = try liveClient.request(action: "observe_game", arguments: [
            "phraseCursor": max(0, phraseCursor),
            "gameLogCursor": max(0, gameLogCursor),
            "bridgeLogCursor": max(0, bridgeLogCursor)
        ])
        return try payload(from: response)
    }

    func getPhrases(limit: Int) throws -> [String] {
        let safeLimit = max(1, limit)
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        let response = try liveClient.request(action: "get_phrases", arguments: [
            "limit": safeLimit
        ])
        return try stringArrayPayload(from: response)
    }

    func getLog(limit: Int) throws -> [String] {
        let safeLimit = max(1, limit)
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        let response = try liveClient.request(action: "get_log", arguments: [
            "limit": safeLimit
        ])
        return try stringArrayPayload(from: response)
    }

    func listDebugScenarios() throws -> [[String: String]] {
        try ensureLiveGameAvailable()
        let response = try liveClient.request(action: "list_debug_scenarios", arguments: [:])
        guard let payload = response["payload"] as? [[String: String]] else {
            throw RuntimeError("Не удалось получить список отладочных сценариев.")
        }
        return payload
    }

    func runDebugScenario(_ name: String) throws -> [String: Any] {
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        let response = try liveClient.request(action: "run_debug_scenario", arguments: [
            "name": name
        ])
        lastLiveCommandAt = Date()
        appendLog("run_debug_scenario: \(name)")
        return try payload(from: response)
    }

    func teleport(roomID: String, x: Int, y: Int) throws -> [String: Any] {
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        let response = try liveClient.request(action: "teleport", arguments: [
            "roomID": roomID,
            "x": x,
            "y": y
        ])
        lastLiveCommandAt = Date()
        appendLog("teleport: \(roomID) \(x),\(y)")
        return try payload(from: response)
    }

    func debugWorld(arguments: [String: Any]) throws -> [String: Any] {
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        let response = try liveClient.request(action: "debug_world", arguments: arguments)
        lastLiveCommandAt = Date()
        appendLog("debug_world: \(arguments["operation"] as? String ?? "?")")
        return try payload(from: response)
    }

    private func ensureLiveGameAvailable() throws {
        if liveClient.ping() {
            return
        }

        guard let liveAppPath else {
            throw RuntimeError("Не найден путь к обычной игре. Нужен FREEWORLD_LIVE_APP_PATH.")
        }

        guard FileManager.default.fileExists(atPath: liveAppPath) else {
            throw RuntimeError("Не нашел собранное приложение игры по пути \(liveAppPath).")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [liveAppPath]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw RuntimeError("Не получилось запустить обычную игру.")
        }

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if liveClient.ping() {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        throw RuntimeError("Обычная игра открылась, но мост управления не ответил.")
    }

    private func payload(from response: [String: Any]) throws -> [String: Any] {
        if (response["ok"] as? Bool) == false {
            throw RuntimeError(response["error"] as? String ?? "Живая игра вернула ошибку.")
        }

        guard let payload = response["payload"] as? [String: Any] else {
            throw RuntimeError("Живая игра вернула непонятное состояние.")
        }

        return payload
    }

    private func stringArrayPayload(from response: [String: Any]) throws -> [String] {
        if (response["ok"] as? Bool) == false {
            throw RuntimeError(response["error"] as? String ?? "Живая игра вернула ошибку.")
        }

        guard let payload = response["payload"] as? [String] else {
            throw RuntimeError("Живая игра вернула непонятный список.")
        }

        return payload
    }

    private func appendLog(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        actionLog.append("[\(timestamp)] \(line)")
        trim(&actionLog)
    }

    private func waitForLiveCommandWindow(for command: GameCommand) {
        let elapsed = Date().timeIntervalSince(lastLiveCommandAt)
        let requiredInterval = interval(for: command)
        if elapsed < requiredInterval {
            Thread.sleep(forTimeInterval: requiredInterval - elapsed)
        }
    }

    private func interval(for command: GameCommand) -> TimeInterval {
        if command.isMovement {
            return liveMovementInterval
        }

        switch command {
        case .describeFocus:
            return liveDescribeInterval
        case .primaryAction, .forceAction, .throwObject, .placeHeldItem:
            return liveActionInterval
        default:
            return liveActionInterval
        }
    }

    private func trim(_ lines: inout [String]) {
        if lines.count > 2000 {
            lines.removeFirst(lines.count - 2000)
        }
    }
}

private extension GameCommand {
    var isMovement: Bool {
        switch self {
        case .moveForward, .moveBackward, .moveLeft, .moveRight:
            return true
        default:
            return false
        }
    }
}
