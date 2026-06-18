import Foundation

#if os(macOS)
import Network

enum LiveGameBridgeDefaults {
    static let host = "127.0.0.1"
    static let port: UInt16 = 47831
}

let liveGameBridgeQueue = DispatchQueue(label: "freeworld.live-bridge.server")

struct LiveGameBridgeError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
#endif
