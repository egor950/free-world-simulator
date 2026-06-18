import Foundation

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
}
