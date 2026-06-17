import Foundation

struct RuntimeError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

protocol MCPToolRuntime {
    func launchLiveGame() throws -> [String: Any]
    func continueGame() throws -> [String: Any]
    func startGame(name: String, kind: String) throws -> [String: Any]
    func press(_ commandName: String) throws -> [String: Any]
    func keyDown(_ commandName: String) throws -> [String: Any]
    func keyUp(_ commandName: String) throws -> [String: Any]
    func holdKey(_ commandName: String, duration: TimeInterval) throws -> [String: Any]
    func getState() throws -> [String: Any]
    func observeGame(phraseCursor: Int, gameLogCursor: Int, bridgeLogCursor: Int) throws -> [String: Any]
    func getPhrases(limit: Int) throws -> [String]
    func getLog(limit: Int) throws -> [String]
    func listDebugScenarios() throws -> [[String: String]]
    func runDebugScenario(_ name: String) throws -> [String: Any]
    func teleport(roomID: String, x: Int, y: Int) throws -> [String: Any]
    func debugWorld(arguments: [String: Any]) throws -> [String: Any]
}

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

final class StdioMCPServer {
    private let runtime: MCPToolRuntime
    private let stdinHandle = FileHandle.standardInput
    private let stdoutHandle = FileHandle.standardOutput
    private var readBuffer = Data()

    init(runtime: MCPToolRuntime) {
        self.runtime = runtime
    }

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
                "tools": StdioMCPServer.toolDefinitions
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
                payload = try runtime.startGame(
                    name: arguments["name"] as? String ?? "Тестер",
                    kind: arguments["kind"] as? String ?? "man"
                )
            case "press":
                guard let command = arguments["command"] as? String else {
                    throw RuntimeError("Для press нужно поле command.")
                }
                payload = try runtime.press(command)
            case "key_down":
                guard let command = arguments["command"] as? String else {
                    throw RuntimeError("Для key_down нужно поле command.")
                }
                payload = try runtime.keyDown(command)
            case "key_up":
                guard let command = arguments["command"] as? String else {
                    throw RuntimeError("Для key_up нужно поле command.")
                }
                payload = try runtime.keyUp(command)
            case "hold_key":
                guard let command = arguments["command"] as? String else {
                    throw RuntimeError("Для hold_key нужно поле command.")
                }
                guard let duration = arguments["duration"] as? Double else {
                    throw RuntimeError("Для hold_key нужно поле duration.")
                }
                payload = try runtime.holdKey(command, duration: duration)
            case "get_state":
                payload = try runtime.getState()
            case "observe_game":
                payload = try runtime.observeGame(
                    phraseCursor: arguments["phraseCursor"] as? Int ?? 0,
                    gameLogCursor: arguments["gameLogCursor"] as? Int ?? 0,
                    bridgeLogCursor: arguments["bridgeLogCursor"] as? Int ?? 0
                )
            case "get_phrases":
                payload = try runtime.getPhrases(limit: arguments["limit"] as? Int ?? 20)
            case "get_log":
                payload = try runtime.getLog(limit: arguments["limit"] as? Int ?? 200)
            case "list_debug_scenarios":
                payload = try runtime.listDebugScenarios()
            case "run_debug_scenario":
                let scenarioName = (arguments["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let scenarioID = (arguments["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedName = scenarioName?.isEmpty == false ? scenarioName : scenarioID
                guard let resolvedName, !resolvedName.isEmpty else {
                    throw RuntimeError("Для run_debug_scenario нужно поле name или id.")
                }
                payload = try runtime.runDebugScenario(resolvedName)
            case "teleport":
                guard let roomID = arguments["roomID"] as? String,
                      let x = arguments["x"] as? Int,
                      let y = arguments["y"] as? Int else {
                    throw RuntimeError("Для teleport нужны roomID, x и y.")
                }
                payload = try runtime.teleport(roomID: roomID, x: x, y: y)
            case "debug_world":
                payload = try runtime.debugWorld(arguments: arguments)
            default:
                throw RuntimeError("Неизвестный инструмент: \(name)")
            }

            respondToolResult(id: id, payload: payload, isError: false)
        } catch let err as RuntimeError {
            respondToolResult(id: id, payload: ["error": err.message], isError: true)
        } catch let err as LiveGameBridgeError {
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
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            return
        }

        let header = "Content-Length: \(data.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else {
            return
        }

        stdoutHandle.write(headerData)
        stdoutHandle.write(data)
    }

    private static let toolDefinitions: [[String: Any]] = [
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
            "name": "key_down",
            "description": "Зажимает игровую команду. Нужно для машины: держать газ, тормоз или руль.",
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
            "name": "key_up",
            "description": "Отпускает ранее зажатую игровую команду.",
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
            "name": "hold_key",
            "description": "Зажимает команду на указанное время и потом отпускает. Удобно для машинных прогонов через MCP.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "command": [
                        "type": "string",
                        "description": "Команда управления."
                    ],
                    "duration": [
                        "type": "number",
                        "description": "Сколько секунд держать кнопку."
                    ]
                ],
                "required": ["command", "duration"]
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
            "name": "observe_game",
            "description": "Тихо наблюдает за живой игрой и возвращает только новые фразы и новые события с прошлого запроса, плюс текущее состояние.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "phraseCursor": [
                        "type": "integer",
                        "description": "Сколько фраз уже было прочитано наблюдателем."
                    ],
                    "gameLogCursor": [
                        "type": "integer",
                        "description": "Сколько игровых строк лога уже было прочитано."
                    ],
                    "bridgeLogCursor": [
                        "type": "integer",
                        "description": "Сколько служебных строк моста уже было прочитано."
                    ]
                ]
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
                        "description": "Имя или id отладочного сценария."
                    ],
                    "id": [
                        "type": "string",
                        "description": "Id отладочного сценария. Можно передавать вместо name."
                    ]
                ],
                "required": []
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
        ],
        [
            "name": "debug_world",
            "description": "Низкоуровневое управление миром. Операции: get_runtime_state, set_player, set_held_item, clear_held_item, set_item_location, clear_item_location, set_state, clear_state, neighbor_set_state, neighbor_loud_step, neighbor_start_break_in, neighbor_attack, neighbor_set_config, refresh.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "operation": [
                        "type": "string",
                        "description": "Имя низкоуровневой debug-операции."
                    ],
                    "itemID": [
                        "type": "string",
                        "description": "ID предмета для операций над предметами."
                    ],
                    "roomID": [
                        "type": "string",
                        "description": "Комната для игрока или предмета."
                    ],
                    "x": [
                        "type": "integer",
                        "description": "Координата X."
                    ],
                    "y": [
                        "type": "integer",
                        "description": "Координата Y."
                    ],
                    "pose": [
                        "type": "string",
                        "description": "Поза игрока: standing, lying, crawling."
                    ],
                    "name": [
                        "type": "string",
                        "description": "Имя предмета в руках."
                    ],
                    "key": [
                        "type": "string",
                        "description": "Сырой ключ состояния."
                    ],
                    "target": [
                        "type": "string",
                        "description": "Удобное имя состояния, например kettle.water, kettle.lid, kettle.placement, mug.fill, stove.stage, tv.stage."
                    ],
                    "value": [
                        "type": "string",
                        "description": "Новое строковое значение состояния."
                    ],
                    "state": [
                        "type": "string",
                        "description": "Состояние соседа: calm, warned, doorbell, breakin, resolved."
                    ],
                    "introText": [
                        "type": "string",
                        "description": "Текст старта штурма соседа."
                    ],
                    "finalText": [
                        "type": "string",
                        "description": "Текст состояния штурма."
                    ],
                    "text": [
                        "type": "string",
                        "description": "Текст для прямой соседской атаки."
                    ],
                    "logLine": [
                        "type": "string",
                        "description": "Строка в лог для соседской атаки."
                    ],
                    "responsePauseMin": [
                        "type": "number",
                        "description": "Минимальная пауза между звонками/стуками соседа."
                    ],
                    "responsePauseMax": [
                        "type": "number",
                        "description": "Максимальная пауза между звонками/стуками соседа."
                    ],
                    "breakInPauseMin": [
                        "type": "number",
                        "description": "Минимальная пауза между ударами при штурме."
                    ],
                    "breakInPauseMax": [
                        "type": "number",
                        "description": "Максимальная пауза между ударами при штурме."
                    ],
                    "hitsTarget": [
                        "type": "integer",
                        "description": "Сколько ударов нужно до пролома."
                    ],
                    "footstepCount": [
                        "type": "integer",
                        "description": "Сколько шагов делает сосед после пролома."
                    ],
                    "footstepPause": [
                        "type": "number",
                        "description": "Пауза между шагами соседа."
                    ],
                    "reset": [
                        "type": "boolean",
                        "description": "Сбросить debug-настройки соседей."
                    ]
                ],
                "required": ["operation"]
            ]
        ]
    ]
}
