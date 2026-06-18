import Foundation

#if os(macOS)
import Network

@MainActor
final class LiveGameBridge {
    static let shared = LiveGameBridge()

    private var viewModel: GameViewModel?
    private var listener: NWListener?
    var spokenPhrases: [String] = []
    var gameLog: [String] = []
    var bridgeLog: [String] = []
    let debugLogURL = FileManager.default.temporaryDirectory.appendingPathComponent("freeworld_live_bridge.log")

    private init() {
        startServerIfNeeded()
    }

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

        case "key_down":
            guard let game = viewModel else {
                throw LiveGameBridgeError("Живая игра еще не запущена. Сначала вызови start_game.")
            }
            guard let rawCommand = arguments["command"] as? String,
                  let command = GameCommand.parse(rawCommand) else {
                throw LiveGameBridgeError("Неизвестная команда для живой игры.")
            }
            game.handleKeyboardInput(.press(command))
            appendBridgeLog("key_down: \(rawCommand)")
            return game.statePayload(recentPhrases: Array(spokenPhrases.suffix(12)))

        case "key_up":
            guard let game = viewModel else {
                throw LiveGameBridgeError("Живая игра еще не запущена. Сначала вызови start_game.")
            }
            guard let rawCommand = arguments["command"] as? String,
                  let command = GameCommand.parse(rawCommand) else {
                throw LiveGameBridgeError("Неизвестная команда для живой игры.")
            }
            game.handleKeyboardInput(.release(command))
            appendBridgeLog("key_up: \(rawCommand)")
            return game.statePayload(recentPhrases: Array(spokenPhrases.suffix(12)))

        case "get_state":
            guard let game = viewModel else {
                throw LiveGameBridgeError("Живая игра еще не запущена. Сначала вызови start_game.")
            }
            return game.statePayload(recentPhrases: Array(spokenPhrases.suffix(12)))

        case "observe_game":
            guard let game = viewModel else {
                throw LiveGameBridgeError("Живая игра еще не запущена. Сначала вызови start_game.")
            }
            let phraseCursor = max(0, arguments["phraseCursor"] as? Int ?? 0)
            let gameLogCursor = max(0, arguments["gameLogCursor"] as? Int ?? 0)
            let bridgeLogCursor = max(0, arguments["bridgeLogCursor"] as? Int ?? 0)
            return observationPayload(
                for: game,
                phraseCursor: phraseCursor,
                gameLogCursor: gameLogCursor,
                bridgeLogCursor: bridgeLogCursor
            )

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

        case "debug_world":
            guard let game = viewModel else {
                throw LiveGameBridgeError("Живая игра еще не запущена. Сначала вызови start_game.")
            }
            guard let operation = arguments["operation"] as? String, !operation.isEmpty else {
                throw LiveGameBridgeError("Для debug_world нужна operation.")
            }
            appendBridgeLog("debug_world: \(operation)")
            return try game.debugWorld(operation: operation, arguments: arguments)

        default:
            throw LiveGameBridgeError("Неизвестное действие для живой игры: \(action)")
        }
    }

    func performEmbeddedAction(_ action: String, arguments: [String: Any]) throws -> Any {
        try handleAction(action, arguments: arguments)
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

    private func observationPayload(
        for game: GameViewModel,
        phraseCursor: Int,
        gameLogCursor: Int,
        bridgeLogCursor: Int
    ) -> [String: Any] {
        var payload = game.statePayload(recentPhrases: Array(spokenPhrases.suffix(12)))
        payload["phraseCursor"] = spokenPhrases.count
        payload["gameLogCursor"] = gameLog.count
        payload["bridgeLogCursor"] = bridgeLog.count
        payload["newPhrases"] = Array(spokenPhrases.dropFirst(min(phraseCursor, spokenPhrases.count)))
        payload["newGameLog"] = Array(gameLog.dropFirst(min(gameLogCursor, gameLog.count)))
        payload["newBridgeLog"] = Array(bridgeLog.dropFirst(min(bridgeLogCursor, bridgeLog.count)))
        return payload
    }
}
#endif
