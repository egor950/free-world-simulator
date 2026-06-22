import Foundation
import GameplayKit

// MARK: - GridPosition Hashable

/// Hashable-расширение для GridPosition, чтобы использовать в Set.
/// Оригинальный тип — только Equatable.
extension GridPosition: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}

// MARK: - NeighborSearchMachine

/// Управляет поиском игрока соседом по комнатам.
///
/// Автомат состояний:
///   Idle → EnteringRoom → SearchingRoom → CheckingFurniture → SearchingRoom → ...
///   SearchingRoom → FoundPlayer  (игрок обнаружен)
///   SearchingRoom → LostPlayer   (все комнаты проверены, игрок не найден)
///
/// Использует BFS-очередь комнат от точки шума. Внутри каждой комнаты
/// проверяет позиции мебели. NeighborHidingSystem.isPlayerDetectable()
/// определяет, найден ли игрок.
final class NeighborSearchMachine {

    // MARK: - States

    private final class IdleState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == EnteringRoomState.self
        }
    }

    private final class EnteringRoomState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == SearchingRoomState.self || stateClass == IdleState.self
        }
    }

    private final class SearchingRoomState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == CheckingFurnitureState.self
                || stateClass == FoundPlayerState.self
                || stateClass == LostPlayerState.self
                || stateClass == IdleState.self
        }
    }

    private final class CheckingFurnitureState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == SearchingRoomState.self
                || stateClass == FoundPlayerState.self
                || stateClass == IdleState.self
        }
    }

    private final class FoundPlayerState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == IdleState.self
        }
    }

    private final class LostPlayerState: GKState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            stateClass == IdleState.self
        }
    }

    // MARK: - Machine

    private let machine: GKStateMachine

    init() {
        machine = GKStateMachine(states: [
            IdleState(),
            EnteringRoomState(),
            SearchingRoomState(),
            CheckingFurnitureState(),
            FoundPlayerState(),
            LostPlayerState(),
        ])
        machine.enter(IdleState.self)
    }

    // MARK: - Public State Queries

    /// Машшина в простое — сосед не ищет.
    var isIdle: Bool { machine.currentState is IdleState }

    /// Сосед активно ищет (идёт в комнату, осматривает или проверяет мебель).
    var isSearching: Bool {
        machine.currentState is SearchingRoomState
            || machine.currentState is EnteringRoomState
            || machine.currentState is CheckingFurnitureState
    }

    /// Игрок обнаружен.
    var foundPlayer: Bool { machine.currentState is FoundPlayerState }

    /// Все комнаты проверены, игрок не найден.
    var lostPlayer: Bool { machine.currentState is LostPlayerState }

    /// Текущая комната, в которой ищет сосед.
    private(set) var currentRoom: RoomID?

    // MARK: - Private Search State

    /// Очередь комнат для проверки (BFS от источника шума).
    private var searchQueue: [RoomID] = []

    /// Уже проверенные позиции в текущей комнате.
    private var checkedPositions: Set<GridPosition> = []

    // MARK: - Public API

    /// Начать поиск из указанной комнаты.
    /// - Parameters:
    ///   - room: Комната, откуда начался шум.
    ///   - availableRooms: Список комнат для обхода (BFS-порядок).
    func beginSearch(from room: RoomID, availableRooms: [RoomID]) {
        currentRoom = room
        searchQueue = availableRooms.filter { $0 != room }
        checkedPositions = []
        _ = machine.enter(EnteringRoomState.self)
    }

    /// Сосед вошёл в комнату — начинаем поиск внутри.
    func enterRoomComplete() {
        _ = machine.enter(SearchingRoomState.self)
    }

    /// Сосед проверяет конкретную позицию (мебель).
    func checkFurniture(at position: GridPosition) {
        checkedPositions.insert(position)
        _ = machine.enter(CheckingFurnitureState.self)
    }

    /// Позиция пуста — продолжаем поиск в комнате.
    func furnitureClear() {
        _ = machine.enter(SearchingRoomState.self)
    }

    /// Игрок обнаружен.
    func playerDetected() {
        _ = machine.enter(FoundPlayerState.self)
    }

    /// Комната проверена, игрок не найден. Переходим к следующей комнате
    /// или завершаем поиск, если очередь пуста.
    func roomClear() {
        if searchQueue.isEmpty {
            _ = machine.enter(LostPlayerState.self)
        } else {
            currentRoom = searchQueue.removeFirst()
            checkedPositions = []
            _ = machine.enter(EnteringRoomState.self)
        }
    }

    /// Полный сброс автомата.
    func reset() {
        currentRoom = nil
        searchQueue = []
        checkedPositions = []
        _ = machine.enter(IdleState.self)
    }

    /// Проверена ли уже данная позиция в текущей комнате.
    func isPositionChecked(_ position: GridPosition) -> Bool {
        checkedPositions.contains(position)
    }
}
