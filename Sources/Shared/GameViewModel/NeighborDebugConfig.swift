import Foundation

/// Отладочная конфигурация для системы соседей.
/// Хранит настройки таймингов и переопределения для тестирования через MCP.
@MainActor
final class NeighborDebugConfig {
    var doorHitsTarget: Int = 0
    var responsePauseRange: ClosedRange<Double>?
    var breakInPauseRange: ClosedRange<Double>?
    var doorHitsTargetOverride: Int?
    var footstepCountOverride: Int?
    var footstepPauseOverride: TimeInterval?

    func reset() {
        doorHitsTarget = 0
        responsePauseRange = nil
        breakInPauseRange = nil
        doorHitsTargetOverride = nil
        footstepCountOverride = nil
        footstepPauseOverride = nil
    }
}
