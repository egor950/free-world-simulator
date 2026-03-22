import Foundation

#if os(macOS)
import Network

enum LiveGameBridgeDefaults {
    static let host = "127.0.0.1"
    static let port: UInt16 = 47831
}

private let liveGameBridgeQueue = DispatchQueue(label: "freeworld.live-bridge.server")

struct LiveGameBridgeClient {
    let host: NWEndpoint.Host
    let port: NWEndpoint.Port

    init(
        host: String = LiveGameBridgeDefaults.host,
        port: UInt16 = LiveGameBridgeDefaults.port
    ) {
        self.host = NWEndpoint.Host(host)
        self.port = NWEndpoint.Port(rawValue: port)!
    }

    func ping(timeout: TimeInterval = 0.5) -> Bool {
        guard let response = try? request(action: "ping", arguments: [:], timeout: timeout) else {
            return false
        }
        return (response["ok"] as? Bool) == true
    }

    func request(
        action: String,
        arguments: [String: Any],
        timeout: TimeInterval = 3
    ) throws -> [String: Any] {
        let connection = NWConnection(host: host, port: port, using: .tcp)
        let queue = DispatchQueue(label: "freeworld.live-bridge.client.\(UUID().uuidString)")
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[String: Any], Error> = .failure(LiveGameBridgeError("Нет ответа от живой игры."))
        var received = Data()

        connection.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                result = .failure(error)
                semaphore.signal()
            case .waiting(let error):
                result = .failure(error)
                semaphore.signal()
            default:
                break
            }
        }

        func receiveLine() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error {
                    result = .failure(error)
                    semaphore.signal()
                    return
                }

                if let data, !data.isEmpty {
                    received.append(data)
                    if let newlineIndex = received.firstIndex(of: 0x0A) {
                        let lineData = received.prefix(upTo: newlineIndex)
                        do {
                            let object = try JSONSerialization.jsonObject(with: lineData, options: [])
                            guard let payload = object as? [String: Any] else {
                                throw LiveGameBridgeError("Живая игра вернула непонятный ответ.")
                            }
                            result = .success(payload)
                        } catch {
                            result = .failure(error)
                        }
                        semaphore.signal()
                        return
                    }
                }

                if isComplete {
                    result = .failure(LiveGameBridgeError("Живая игра закрыла соединение раньше времени."))
                    semaphore.signal()
                    return
                }

                receiveLine()
            }
        }

        connection.start(queue: queue)
        receiveLine()

        let payload = try JSONSerialization.data(withJSONObject: [
            "action": action,
            "arguments": arguments
        ])
        var message = Data(payload)
        message.append(0x0A)

        connection.send(content: message, completion: .contentProcessed { error in
            if let error {
                result = .failure(error)
                semaphore.signal()
            }
        })

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            connection.cancel()
            throw LiveGameBridgeError("Живая игра не ответила вовремя.")
        }

        connection.cancel()
        return try result.get()
    }
}

@MainActor
final class LiveGameBridge {
    static let shared = LiveGameBridge()

    private var viewModel: GameViewModel?
    private var listener: NWListener?
    private var spokenPhrases: [String] = []
    private var gameLog: [String] = []
    private var bridgeLog: [String] = []
    private let debugLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("freeworld_live_bridge.log")

    func makeViewModel(onGameFinished: (() -> Void)? = nil) -> GameViewModel {
        if let viewModel {
            startServerIfNeeded()
            return viewModel
        }

        let speech = SpeechCoordinator(isMuted: false) { [weak self] text in
            Task { @MainActor in
                self?.appendPhrase(text)
            }
        }
        let audio = AudioCoordinator(isMuted: false)
        let viewModel = GameViewModel(
            speechCoordinator: speech,
            audioCoordinator: audio,
            onLogLine: { [weak self] line in
                Task { @MainActor in
                    self?.appendGameLog(line)
                }
            },
            onGameFinished: onGameFinished
        )

        self.viewModel = viewModel
        startServerIfNeeded()
        return viewModel
    }

    private func startServerIfNeeded() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let port = NWEndpoint.Port(rawValue: LiveGameBridgeDefaults.port)!
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    Task { @MainActor in
                        self?.appendBridgeLog("bridge_failed: \(error.localizedDescription)")
                    }
                }
            }
            listener.start(queue: liveGameBridgeQueue)
            self.listener = listener
            appendBridgeLog("bridge_started")
        } catch {
            appendBridgeLog("bridge_failed: \(error.localizedDescription)")
        }
    }

    nonisolated private func handle(_ connection: NWConnection) {
        connection.start(queue: liveGameBridgeQueue)
        readRequest(from: connection, buffer: Data())
    }

    nonisolated private func readRequest(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                connection.cancel()
                Task { @MainActor in
                    self.appendBridgeLog("receive_failed: \(error.localizedDescription)")
                }
                return
            }

            var nextBuffer = buffer
            if let data, !data.isEmpty {
                nextBuffer.append(data)
            }

            if let newlineIndex = nextBuffer.firstIndex(of: 0x0A) {
                let line = Data(nextBuffer.prefix(upTo: newlineIndex))
                Task { @MainActor in
                    let response = self.process(line)
                    self.send(response, through: connection)
                }
                return
            }

            if isComplete {
                connection.cancel()
                return
            }

            self.readRequest(from: connection, buffer: nextBuffer)
        }
    }

    private func process(_ line: Data) -> [String: Any] {
        do {
            let object = try JSONSerialization.jsonObject(with: line, options: [])
            guard let request = object as? [String: Any] else {
                throw LiveGameBridgeError("Непонятный запрос к живой игре.")
            }

            let action = request["action"] as? String ?? ""
            let arguments = request["arguments"] as? [String: Any] ?? [:]
            let payload = try handleAction(action, arguments: arguments)
            return [
                "ok": true,
                "payload": payload
            ]
        } catch let error as LiveGameBridgeError {
            return [
                "ok": false,
                "error": error.message
            ]
        } catch {
            return [
                "ok": false,
                "error": error.localizedDescription
            ]
        }
    }

    private func handleAction(_ action: String, arguments: [String: Any]) throws -> Any {
        switch action {
        case "ping":
            return [
                "listening": true,
                "hasViewModel": viewModel != nil
            ]

        case "start_game":
            let game = makeViewModel()
            let name = arguments["name"] as? String ?? "Тестер"
            let kind = arguments["kind"] as? String ?? "man"
            spokenPhrases.removeAll()
            gameLog.removeAll()
            bridgeLog.removeAll()
            appendBridgeLog("start_game: \(name), \(kind)")
            game.resetForNewSession()
            game.continueFromWelcome()
            game.selectedCharacterKind = kind.lowercased() == "woman" ? .woman : .man
            game.characterName = name
            game.finishCharacterCreation()
            return game.statePayload(recentPhrases: Array(spokenPhrases.suffix(12)))

        case "continue_game":
            guard let game = viewModel else {
                throw LiveGameBridgeError("Живая игра еще не запущена. Сначала вызови start_game.")
            }
            appendBridgeLog("continue_game")
            return game.statePayload(recentPhrases: Array(spokenPhrases.suffix(12)))

        case "press":
            guard let game = viewModel else {
                throw LiveGameBridgeError("Живая игра еще не запущена. Сначала вызови start_game.")
            }
            guard let rawCommand = arguments["command"] as? String,
                  let command = GameCommand.parse(rawCommand) else {
                throw LiveGameBridgeError("Неизвестная команда для живой игры.")
            }
            game.handle(command)
            appendBridgeLog("press: \(rawCommand)")
            return game.statePayload(recentPhrases: Array(spokenPhrases.suffix(12)))

        case "get_state":
            guard let game = viewModel else {
                throw LiveGameBridgeError("Живая игра еще не запущена. Сначала вызови start_game.")
            }
            return game.statePayload(recentPhrases: Array(spokenPhrases.suffix(12)))

        case "get_phrases":
            let limit = max(1, arguments["limit"] as? Int ?? 20)
            return Array(spokenPhrases.suffix(limit))

        case "get_log":
            let limit = max(1, arguments["limit"] as? Int ?? 200)
            return Array((bridgeLog + gameLog).suffix(limit))

        case "list_debug_scenarios":
            let game = makeViewModel()
            return game.availableDebugScenarios()

        case "run_debug_scenario":
            guard let game = viewModel else {
                throw LiveGameBridgeError("Живая игра еще не запущена. Сначала вызови start_game.")
            }
            guard let name = arguments["name"] as? String, !name.isEmpty else {
                throw LiveGameBridgeError("Нужно имя сценария.")
            }
            guard game.runDebugScenario(named: name) else {
                throw LiveGameBridgeError("Неизвестный отладочный сценарий: \(name)")
            }
            appendBridgeLog("run_debug_scenario: \(name)")
            return game.statePayload(recentPhrases: Array(spokenPhrases.suffix(12)))

        case "teleport":
            guard let game = viewModel else {
                throw LiveGameBridgeError("Живая игра еще не запущена. Сначала вызови start_game.")
            }
            guard let roomID = arguments["roomID"] as? String,
                  let x = arguments["x"] as? Int,
                  let y = arguments["y"] as? Int else {
                throw LiveGameBridgeError("Для teleport нужны roomID, x и y.")
            }
            guard game.debugTeleport(roomID: roomID, x: x, y: y) else {
                throw LiveGameBridgeError("Не удалось телепортировать игрока.")
            }
            appendBridgeLog("teleport: \(roomID) \(x),\(y)")
            return game.statePayload(recentPhrases: Array(spokenPhrases.suffix(12)))

        default:
            throw LiveGameBridgeError("Неизвестное действие для живой игры: \(action)")
        }
    }

    private func send(_ response: [String: Any], through connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: response, options: []) else {
            connection.cancel()
            return
        }

        var message = Data(data)
        message.append(0x0A)
        connection.send(content: message, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func appendPhrase(_ text: String) {
        spokenPhrases.append(text)
        trim(&spokenPhrases)
    }

    private func appendGameLog(_ line: String) {
        gameLog.append(timestamped("game", line))
        trim(&gameLog)
    }

    private func appendBridgeLog(_ line: String) {
        let rendered = timestamped("bridge", line)
        bridgeLog.append(rendered)
        trim(&bridgeLog)
        appendDebugFileLine(rendered)
    }

    private func timestamped(_ source: String, _ line: String) -> String {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return "[\(timestamp)] \(source): \(line)"
    }

    private func trim(_ lines: inout [String]) {
        if lines.count > 2000 {
            lines.removeFirst(lines.count - 2000)
        }
    }

    private func appendDebugFileLine(_ line: String) {
        let rendered = line + "\n"
        let data = Data(rendered.utf8)

        if FileManager.default.fileExists(atPath: debugLogURL.path) {
            if let handle = try? FileHandle(forWritingTo: debugLogURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
            return
        }

        try? data.write(to: debugLogURL, options: .atomic)
    }
}

struct LiveGameBridgeError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
#endif
