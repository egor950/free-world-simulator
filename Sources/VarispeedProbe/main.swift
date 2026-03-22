import AVFoundation
import Foundation

struct ProbeStep {
    let rate: Float
    let duration: TimeInterval
    let title: String
}

enum ProbeError: LocalizedError {
    case missingAudioFile(String)
    case failedToCreateBuffer

    var errorDescription: String? {
        switch self {
        case .missingAudioFile(let details):
            return details
        case .failedToCreateBuffer:
            return "Не удалось подготовить аудио-буфер для проверки Varispeed."
        }
    }
}

final class VarispeedProbe {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let varispeed = AVAudioUnitVarispeed()

    func run(with fileURL: URL) throws {
        let audioFile = try AVAudioFile(forReading: fileURL)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: AVAudioFrameCount(audioFile.length)
        ) else {
            throw ProbeError.failedToCreateBuffer
        }

        try audioFile.read(into: buffer)

        engine.attach(player)
        engine.attach(varispeed)
        engine.connect(player, to: varispeed, format: buffer.format)
        engine.connect(varispeed, to: engine.mainMixerNode, format: buffer.format)

        try engine.start()
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        player.volume = 0.92
        player.play()

        print("Файл: \(fileURL.path)")
        print("Сейчас пойдет явная проверка Varispeed. Если всё работает, звук будет очень заметно меняться.")

        let steps: [ProbeStep] = [
            ProbeStep(rate: 0.55, duration: 2.2, title: "Очень медленно и низко"),
            ProbeStep(rate: 0.80, duration: 2.0, title: "Медленно"),
            ProbeStep(rate: 1.00, duration: 2.0, title: "Нормально"),
            ProbeStep(rate: 1.35, duration: 2.0, title: "Быстро и выше"),
            ProbeStep(rate: 1.75, duration: 2.2, title: "Очень быстро и сильно выше"),
            ProbeStep(rate: 0.70, duration: 2.0, title: "Снова вниз"),
            ProbeStep(rate: 1.15, duration: 2.0, title: "Чуть быстрее нормы")
        ]

        for step in steps {
            varispeed.rate = step.rate
            print(String(format: "rate=%.2f  |  %@", step.rate, step.title))
            Thread.sleep(forTimeInterval: step.duration)
        }

        player.stop()
        engine.stop()
        print("Проверка закончилась.")
    }
}

func resolveAudioURL(from arguments: [String]) throws -> URL {
    let fileManager = FileManager.default

    if arguments.count > 1 {
        let explicitURL = URL(fileURLWithPath: arguments[1])
        if fileManager.fileExists(atPath: explicitURL.path) {
            return explicitURL
        }
    }

    let candidates = [
        URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("Resources/Audio/traffic_engine_sedan.wav"),
        URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent("Resources/Audio/traffic_engine_base.wav"),
        Bundle.main.resourceURL?.appendingPathComponent("traffic_engine_sedan.wav"),
        Bundle.main.resourceURL?.appendingPathComponent("traffic_engine_base.wav")
    ].compactMap { $0 }

    if let found = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
        return found
    }

    throw ProbeError.missingAudioFile(
        """
        Не нашёл файл мотора для проверки.
        Можно запустить так:
        FreeWorldVarispeedProbe /полный/путь/к/traffic_engine_sedan.wav
        """
    )
}

do {
    let url = try resolveAudioURL(from: CommandLine.arguments)
    try VarispeedProbe().run(with: url)
} catch {
    fputs("Ошибка: \(error.localizedDescription)\n", stderr)
    exit(1)
}
