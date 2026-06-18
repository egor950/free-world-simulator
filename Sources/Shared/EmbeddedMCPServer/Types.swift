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
