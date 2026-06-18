import Foundation

#if os(macOS)

extension LiveGameBridge {
    func appendPhrase(_ text: String) {
        spokenPhrases.append(text)
        trim(&spokenPhrases)
    }

    func appendGameLog(_ line: String) {
        gameLog.append(timestamped("game", line))
        trim(&gameLog)
    }

    func appendBridgeLog(_ line: String) {
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
#endif
