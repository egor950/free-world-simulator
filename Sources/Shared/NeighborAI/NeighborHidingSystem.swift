import Foundation
// Типы из WorldCore: RoomID, GridPosition, RoomDefinition, DoorDefinition, FocusNode

/// Тип укрытия
enum HidingType {
    case behindDoor
    case behindFurniture
    case inBed  // кровать — безопасная зона, нельзя найти
}

/// Место для укрытия
struct HidingSpot {
    let roomID: RoomID
    let position: GridPosition
    let type: HidingType
}

/// Система укрытия игрока от соседа.
/// Игрок нажимает H рядом с укрытием (мебель/дверь), чтобы спрятаться.
/// Кровать — безопасная зона, сосед не может найти игрока.
@MainActor
final class NeighborHidingSystem {
    private(set) var isHiding: Bool = false
    private(set) var isInBed: Bool = false
    private(set) var currentSpot: HidingSpot?

    /// Может ли игрок спрятаться в текущей позиции?
    func canHide(playerPosition: GridPosition, roomDef: RoomDefinition) -> Bool {
        !availableHidingSpots(playerPosition: playerPosition, roomDef: roomDef).isEmpty
    }

    /// Получить доступные места для укрытия рядом с игроком
    func availableHidingSpots(
        playerPosition: GridPosition,
        roomDef: RoomDefinition
    ) -> [HidingSpot] {
        var spots: [HidingSpot] = []

        // Проверяем двери — дверь рядом = можно спрятаться за ней
        for (_, door) in roomDef.doors {
            guard let node = roomDef.nodes.first(where: { $0.id == door.focusNodeID }) else {
                continue
            }
            if isAdjacent(playerPosition, node.position) {
                spots.append(
                    HidingSpot(
                        roomID: roomDef.id,
                        position: node.position,
                        type: .behindDoor
                    )
                )
            }
        }

        // Проверяем мебель (узлы с target == .item)
        for node in roomDef.nodes {
            guard case .item = node.target else { continue }
            if isAdjacent(playerPosition, node.position) {
                spots.append(
                    HidingSpot(
                        roomID: roomDef.id,
                        position: node.position,
                        type: .behindFurniture
                    )
                )
            }
        }

        return spots
    }

    /// Спрятаться в указанном месте (вызывается при нажатии H)
    func hide(in spot: HidingSpot) {
        isHiding = true
        currentSpot = spot

        if spot.type == .inBed {
            isInBed = true
        }
    }

    /// Выйти из укрытия (при движении или вставании)
    func exitHiding() {
        isHiding = false
        isInBed = false
        currentSpot = nil
    }

    /// Может ли сосед обнаружить игрока?
    func isPlayerDetectable() -> Bool {
        !isHiding && !isInBed
    }

    /// Текущее место — безопасная зона (кровать)?
    func isSafeZone() -> Bool {
        isInBed
    }

    /// Проверяет, стоит ли игрок на кровати по ID узла
    func checkBedPosition(
        playerPosition: GridPosition,
        roomDef: RoomDefinition
    ) -> Bool {
        for node in roomDef.nodes {
            // Кровать — узел с id, содержащим "bed"
            if node.id.lowercased().contains("bed")
                && node.position == playerPosition
            {
                return true
            }
        }
        return false
    }

    /// Сбросить состояние к начальному
    func reset() {
        isHiding = false
        isInBed = false
        currentSpot = nil
    }

    // MARK: - Private

    /// Две позиции рядом (на расстоянии 1 клетки по одной из осей)
    private func isAdjacent(_ a: GridPosition, _ b: GridPosition) -> Bool {
        let dx = abs(a.x - b.x)
        let dy = abs(a.y - b.y)
        return dx + dy == 1
    }
}
