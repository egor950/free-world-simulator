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

    func getState() throws -> [String: Any] {
        guard hasActiveSession else {
            throw RuntimeError("Сессия игры не запущена. Сначала вызови start_game.")
        }
        let response = try liveClient.request(action: "get_state", arguments: [:])
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

@MainActor
final class MCPServer {
    private let runtime = GameRuntime()
    private let stdinHandle = FileHandle.standardInput
    private let stdoutHandle = FileHandle.standardOutput
    private var readBuffer = Data()

    func run() {
        while let body = readNextMessage() {
            handleIncomingBody(body)
        }
    }

    private func readNextMessage() -> Data? {
        while true {
            if let body = extractOneMessage() {
                return body
            }

            let chunk = stdinHandle.availableData
            if chunk.isEmpty {
                return nil
            }
            readBuffer.append(chunk)
        }
    }

    private func extractOneMessage() -> Data? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = readBuffer.range(of: separator) else {
            return nil
        }

        let headerData = readBuffer.subdata(in: 0..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            readBuffer.removeAll()
            return nil
        }

        var contentLength: Int?
        for line in headerText.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].lowercased() == "content-length" {
                contentLength = Int(parts[1])
            }
        }

        guard let length = contentLength else {
            readBuffer.removeAll()
            return nil
        }

        let bodyStart = headerRange.upperBound
        let neededCount = bodyStart + length
        guard readBuffer.count >= neededCount else {
            return nil
        }

        let body = readBuffer.subdata(in: bodyStart..<neededCount)
        readBuffer.removeSubrange(0..<neededCount)
        return body
    }

    private func handleIncomingBody(_ body: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = object["method"] as? String else {
            return
        }

        let id = object["id"]
        let params = object["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            respond(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [:]
                ],
                "serverInfo": [
                    "name": "freeworld-mcp",
                    "version": "2.0.0"
                ]
            ])

        case "notifications/initialized":
            break

        case "ping":
            respond(id: id, result: [:])

        case "tools/list":
            respond(id: id, result: [
                "tools": [
                    [
                        "name": "launch_live_game",
                        "description": "Открывает обычную игру со звуком и готовит ее к живому управлению.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [:]
                        ]
                    ],
                    [
                        "name": "continue_game",
                        "description": "Подключается к уже идущей живой игре и продолжает с текущего места без нового старта.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [:]
                        ]
                    ],
                    [
                        "name": "start_game",
                        "description": "Запускает новую игру и создает персонажа в обычной живой игре со звуком.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "name": [
                                    "type": "string",
                                    "description": "Имя персонажа. По умолчанию Тестер."
                                ],
                                "kind": [
                                    "type": "string",
                                    "description": "man или woman. По умолчанию man."
                                ]
                            ]
                        ]
                    ],
                    [
                        "name": "press",
                        "description": "Нажимает игровую команду: forward/backward/left/right/action/force/throw/describe/place.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "command": [
                                    "type": "string",
                                    "description": "Команда управления."
                                ]
                            ],
                            "required": ["command"]
                        ]
                    ],
                    [
                        "name": "get_state",
                        "description": "Возвращает текущее состояние игры: комната, что рядом, статус и позиция.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [:]
                        ]
                    ],
                    [
                        "name": "get_phrases",
                        "description": "Возвращает последние озвученные фразы из текущей игры.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "limit": [
                                    "type": "integer",
                                    "description": "Сколько последних фраз вернуть. По умолчанию 20."
                                ]
                            ]
                        ]
                    ],
                    [
                        "name": "get_log",
                        "description": "Возвращает подробный лог действий сервера или живой игры.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "limit": [
                                    "type": "integer",
                                    "description": "Сколько строк вернуть. По умолчанию 200."
                                ]
                            ]
                        ]
                    ],
                    [
                        "name": "list_debug_scenarios",
                        "description": "Показывает готовые отладочные сцены и точки для быстрой проверки механик.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [:]
                        ]
                    ],
                    [
                        "name": "run_debug_scenario",
                        "description": "Запускает готовую отладочную сцену, например припаркованную машину, кровать или холодильник.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "name": [
                                    "type": "string",
                                    "description": "Имя отладочного сценария."
                                ]
                            ],
                            "required": ["name"]
                        ]
                    ],
                    [
                        "name": "teleport",
                        "description": "Мгновенно переносит игрока в нужную комнату и точку для ручной проверки механики.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "roomID": [
                                    "type": "string",
                                    "description": "Комната: hallway, bedroom, livingRoom, kitchen, bathroom, street."
                                ],
                                "x": [
                                    "type": "integer",
                                    "description": "Координата по ширине."
                                ],
                                "y": [
                                    "type": "integer",
                                    "description": "Координата по высоте."
                                ]
                            ],
                            "required": ["roomID", "x", "y"]
                        ]
                    ]
                ]
            ])

        case "tools/call":
            handleToolCall(id: id, params: params)

        default:
            if id != nil {
                respondError(id: id, code: -32601, message: "Method not found: \(method)")
            }
        }
    }

    private func handleToolCall(id: Any?, params: [String: Any]) {
        guard let name = params["name"] as? String else {
            respondError(id: id, code: -32602, message: "Missing tool name")
            return
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        do {
            let payload: Any
            switch name {
            case "launch_live_game":
                payload = try runtime.launchLiveGame()

            case "continue_game":
                payload = try runtime.continueGame()

            case "start_game":
                let characterName = arguments["name"] as? String ?? "Тестер"
                let kind = arguments["kind"] as? String ?? "man"
                payload = try runtime.startGame(name: characterName, kind: kind)

            case "press":
                guard let command = arguments["command"] as? String else {
                    throw RuntimeError("Для press нужно поле command.")
                }
                payload = try runtime.press(command)

            case "get_state":
                payload = try runtime.getState()

            case "get_phrases":
                let limit = arguments["limit"] as? Int ?? 20
                payload = try runtime.getPhrases(limit: limit)

            case "get_log":
                let limit = arguments["limit"] as? Int ?? 200
                payload = try runtime.getLog(limit: limit)

            case "list_debug_scenarios":
                payload = try runtime.listDebugScenarios()

            case "run_debug_scenario":
                guard let name = arguments["name"] as? String, !name.isEmpty else {
                    throw RuntimeError("Для run_debug_scenario нужно поле name.")
                }
                payload = try runtime.runDebugScenario(name)

            case "teleport":
                guard let roomID = arguments["roomID"] as? String,
                      let x = arguments["x"] as? Int,
                      let y = arguments["y"] as? Int else {
                    throw RuntimeError("Для teleport нужны roomID, x и y.")
                }
                payload = try runtime.teleport(roomID: roomID, x: x, y: y)

            default:
                throw RuntimeError("Неизвестный инструмент: \(name)")
            }

            respondToolResult(id: id, payload: payload, isError: false)
        } catch let err as RuntimeError {
            respondToolResult(id: id, payload: ["error": err.message], isError: true)
        } catch {
            respondToolResult(id: id, payload: ["error": String(describing: error)], isError: true)
        }
    }

    private func respond(id: Any?, result: Any) {
        var object: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result
        ]
        if let id {
            object["id"] = id
        }
        writeMessage(object)
    }

    private func respondError(id: Any?, code: Int, message: String) {
        var object: [String: Any] = [
            "jsonrpc": "2.0",
            "error": [
                "code": code,
                "message": message
            ]
        ]
        if let id {
            object["id"] = id
        }
        writeMessage(object)
    }

    private func respondToolResult(id: Any?, payload: Any, isError: Bool) {
        let text: String
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            text = string
        } else {
            text = String(describing: payload)
        }

        respond(id: id, result: [
            "content": [
                [
                    "type": "text",
                    "text": text
                ]
            ],
            "isError": isError
        ])
    }

    private func writeMessage(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let header = "Content-Length: \(data.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else { return }
        stdoutHandle.write(headerData)
        stdoutHandle.write(data)
    }
}

Task { @MainActor in
    let server = MCPServer()
    server.run()
    exit(0)
}

dispatchMain()
