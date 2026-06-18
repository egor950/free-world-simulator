import Foundation

#if os(macOS)
import Network

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
#endif
