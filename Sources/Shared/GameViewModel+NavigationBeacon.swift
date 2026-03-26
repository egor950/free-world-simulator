import Foundation

struct NavigationBeaconLocation {
    let id: String
    let title: String
    let roomID: RoomID
    let position: GridPosition
}

private enum NavigationBeaconStage {
    case streetLine
    case streetDoor
    case storeCounter
}

extension GameViewModel {
    var availableNavigationLocations: [NavigationBeaconLocation] {
        [
            NavigationBeaconLocation(
                id: "grocery_store",
                title: "Продуктовый",
                roomID: .mainStreet,
                position: MainStreetRoom.groceryDoorPosition
            )
        ]
    }

    func toggleLocationMenu() {
        if isLocationMenuOpen {
            closeLocationMenu(announceClose: true)
            return
        }

        isLocationMenuOpen = true
        if selectedLocationMenuIndex >= availableNavigationLocations.count {
            selectedLocationMenuIndex = 0
        }
        refreshLocationMenuText()
        announce("\(locationMenuTitle). \(locationMenuText)")
    }

    func closeLocationMenu(announceClose: Bool = false) {
        isLocationMenuOpen = false
        locationMenuTitle = ""
        locationMenuText = ""
        if announceClose {
            announce("Меню маяка закрыто.")
        }
    }

    func confirmLocationMenuSelection() {
        guard isLocationMenuOpen else {
            announce("Меню маяка сейчас закрыто.")
            return
        }

        let location = availableNavigationLocations[selectedLocationMenuIndex]
        activeNavigationBeaconID = location.id
        closeLocationMenu(announceClose: false)
        startNavigationBeaconLoop()
        announce("Маяк включен: \(location.title). Он доведет сначала до двери, а потом до прилавка. \(navigationBeaconGuidanceText(for: location))")
    }

    func stopNavigationBeacon(announceStop: Bool) {
        activeNavigationBeaconID = nil
        navigationBeaconTask?.cancel()
        navigationBeaconTask = nil
        if announceStop {
            announce("Маяк выключен.")
        }
    }

    func handleLocationMenuCommand(_ command: GameCommand) {
        switch command {
        case .moveLeft, .moveBackward:
            selectedLocationMenuIndex = max(0, selectedLocationMenuIndex - 1)
            refreshLocationMenuText()
            announce(locationMenuText)
        case .moveRight, .moveForward:
            selectedLocationMenuIndex = min(availableNavigationLocations.count - 1, selectedLocationMenuIndex + 1)
            refreshLocationMenuText()
            announce(locationMenuText)
        case .locationMenuConfirm, .primaryAction:
            confirmLocationMenuSelection()
        case .locationMenuToggle, .inventoryToggle:
            closeLocationMenu(announceClose: true)
        default:
            announce("В меню маяка используй стрелки для выбора, Enter для подтверждения и X для закрытия.")
        }
    }

    func syncNavigationBeaconState() {
        guard let location = activeNavigationLocation else {
            navigationBeaconTask?.cancel()
            navigationBeaconTask = nil
            return
        }

        if hasReachedNavigationLocation(location) {
            activeNavigationBeaconID = nil
            navigationBeaconTask?.cancel()
            navigationBeaconTask = nil
            announce("Ты дошел до прилавка продуктового. Маяк выключен.")
        }
    }

    func currentNavigationBeaconHint() -> String? {
        guard let location = activeNavigationLocation else {
            return nil
        }
        guard !hasReachedNavigationLocation(location) else {
            return nil
        }
        return navigationBeaconGuidanceText(for: location)
    }

    private var activeNavigationLocation: NavigationBeaconLocation? {
        availableNavigationLocations.first { $0.id == activeNavigationBeaconID }
    }

    private func refreshLocationMenuText() {
        guard !availableNavigationLocations.isEmpty else {
            locationMenuTitle = "Маяк"
            locationMenuText = "Пока нет доступных точек."
            return
        }

        let location = availableNavigationLocations[selectedLocationMenuIndex]
        locationMenuTitle = "Выбор точки"
        locationMenuText = "Сейчас выбрано: \(location.title). Нажми Enter, чтобы включить маяк."
    }

    private func startNavigationBeaconLoop() {
        navigationBeaconTask?.cancel()
        navigationBeaconTask = Task { @MainActor [weak self] in
            while let self, let location = self.activeNavigationLocation {
                if self.hasReachedNavigationLocation(location) {
                    self.activeNavigationBeaconID = nil
                    break
                }

                self.audioCoordinator.playNavigationMarker(pan: self.navigationBeaconPan(for: location))
                let delay = self.navigationBeaconPulseDelay(for: location)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
            }
            self?.navigationBeaconTask = nil
        }
    }

    private func navigationBeaconPulseDelay(for location: NavigationBeaconLocation) -> TimeInterval {
        let distance = navigationBeaconDistance(to: location)
        switch distance {
        case ...2:
            return 0.35
        case ...6:
            return 0.55
        case ...14:
            return 0.8
        default:
            return 1.1
        }
    }

    private func navigationBeaconDistance(to location: NavigationBeaconLocation) -> Int {
        switch navigationBeaconStage(for: location) {
        case .streetLine:
            return abs(MainStreetRoom.groceryDoorPosition.y - state.player.roomPosition.y)
        case .streetDoor:
            guard state.player.roomID == .mainStreet else {
                return 99
            }
            let targetPosition = nearestStoreDoorPosition(from: state.player.roomPosition)
            return manhattanDistance(from: state.player.roomPosition, to: targetPosition)
        case .storeCounter:
            guard state.player.roomID == .groceryStore else {
                return 99
            }
            return manhattanDistance(from: state.player.roomPosition, to: GroceryStoreRoom.counterPosition)
        case nil:
            return 99
        }
    }

    private func hasReachedNavigationLocation(_ location: NavigationBeaconLocation) -> Bool {
        if location.id == "grocery_store" {
            return state.player.roomID == .groceryStore &&
                state.player.roomPosition == GroceryStoreRoom.counterPosition
        }
        return false
    }

    private func navigationBeaconGuidanceText(for location: NavigationBeaconLocation) -> String {
        if state.player.roomID != .mainStreet && state.player.roomID != .groceryStore {
            switch state.player.roomID {
            case .street:
                return "Сначала дойди до калитки и выйди на большую улицу."
            case .hallway, .bedroom, .livingRoom, .kitchen, .bathroom:
                return "Сначала выйди из квартиры и дойди до большой улицы."
            default:
                return "Сначала вернись на большую улицу."
            }
        }

        guard let stage = navigationBeaconStage(for: location) else {
            return "Сначала вернись на большую улицу."
        }

        switch stage {
        case .streetLine:
            let dy = MainStreetRoom.groceryDoorPosition.y - state.player.roomPosition.y
            let distance = abs(dy)
            if distance == 0 {
                return "Ты уже на линии магазина. Теперь иди вправо к фасаду."
            }
            if dy < 0 {
                return "Сначала дойди до линии магазина. Иди вперед. До нужного уровня примерно \(distance) шагов."
            }
            return "Сначала вернись к линии магазина. Иди назад. До нужного уровня примерно \(distance) шагов."

        case .streetDoor:
            let targetPosition = nearestStoreDoorPosition(from: state.player.roomPosition)
            let dx = targetPosition.x - state.player.roomPosition.x
            let dy = targetPosition.y - state.player.roomPosition.y
            let distance = manhattanDistance(from: state.player.roomPosition, to: targetPosition)

            if MainStreetRoom.groceryDoorPositions.contains(state.player.roomPosition) {
                return "Вход прямо здесь. Открой дверь и иди вправо."
            }

            if state.player.roomPosition.x == MainStreetRoom.width - 1 {
                return wallGuidanceAlongStorefront(for: dy)
            }

            if dx > 0 {
                return "Теперь фасад и дверь справа. Иди вправо. До двери примерно \(distance) шагов."
            }
            if dx < 0 {
                return "Ты уже прошел мимо линии двери. Вернись влево."
            }
            if dy < 0 {
                return "Ты уже у фасада. Дверь чуть впереди вдоль стены."
            }
            return "Ты уже у фасада. Дверь чуть позади вдоль стены."

        case .storeCounter:
            let dx = GroceryStoreRoom.counterPosition.x - state.player.roomPosition.x
            let dy = GroceryStoreRoom.counterPosition.y - state.player.roomPosition.y
            let distance = manhattanDistance(from: state.player.roomPosition, to: GroceryStoreRoom.counterPosition)

            if distance == 0 {
                return "Прилавок прямо здесь."
            }

            if abs(dx) > max(1, abs(dy)) {
                if dx > 0 {
                    return "Ты уже внутри магазина. Прилавок справа. Иди вправо. До него примерно \(distance) шагов."
                }
                return "Ты уже внутри магазина. Прилавок слева. Иди влево. До него примерно \(distance) шагов."
            }

            if abs(dy) > max(1, abs(dx)) {
                if dy < 0 {
                    return "Ты уже внутри магазина. Прилавок впереди. Иди вперед. До него примерно \(distance) шагов."
                }
                return "Ты уже внутри магазина. Прилавок позади. Иди назад. До него примерно \(distance) шагов."
            }

            if dy == 0 {
                if dx > 0 {
                    return "Ты уже внутри магазина. Прилавок прямо справа. Иди вправо."
                }
                return "Ты уже внутри магазина. Прилавок прямо слева. Иди влево."
            }

            if dx == 0 {
                if dy < 0 {
                    return "Ты уже внутри магазина. Прилавок прямо впереди. Иди вперед."
                }
                return "Ты уже внутри магазина. Прилавок прямо позади. Иди назад."
            }

            if dy < 0 && dx > 0 {
                return "Прилавок впереди и немного справа. Иди вперед, потом чуть вправо."
            }
            if dy < 0 && dx < 0 {
                return "Прилавок впереди и немного слева. Иди вперед, потом чуть влево."
            }
            if dy > 0 && dx > 0 {
                return "Прилавок позади и немного справа. Вернись назад, потом чуть вправо."
            }
            return "Прилавок позади и немного слева. Вернись назад, потом чуть влево."
        }
    }

    private func navigationBeaconPan(for location: NavigationBeaconLocation) -> Float {
        guard let stage = navigationBeaconStage(for: location) else {
            return 0
        }

        switch stage {
        case .streetLine:
            return 0
        case .streetDoor:
            let targetPosition = nearestStoreDoorPosition(from: state.player.roomPosition)
            let dx = targetPosition.x - state.player.roomPosition.x
            if state.player.roomPosition.x == MainStreetRoom.width - 1 {
                return 0
            }
            let pan = Float(dx) / 8.0
            return max(-1, min(1, pan))
        case .storeCounter:
            let dx = GroceryStoreRoom.counterPosition.x - state.player.roomPosition.x
            let pan = Float(dx) / 6.0
            return max(-1, min(1, pan))
        }
    }

    private func nearestStoreDoorPosition(from origin: GridPosition) -> GridPosition {
        MainStreetRoom.groceryDoorPositions.min(by: {
            manhattanDistance(from: $0, to: origin) < manhattanDistance(from: $1, to: origin)
        }) ?? MainStreetRoom.groceryDoorPosition
    }

    private func navigationBeaconStage(for location: NavigationBeaconLocation) -> NavigationBeaconStage? {
        guard location.id == "grocery_store" else {
            return nil
        }

        switch state.player.roomID {
        case .mainStreet:
            if abs(state.player.roomPosition.y - MainStreetRoom.groceryDoorPosition.y) > 3 {
                return .streetLine
            }
            return .streetDoor
        case .groceryStore:
            return .storeCounter
        default:
            return nil
        }
    }

    private func wallGuidanceAlongStorefront(for dy: Int) -> String {
        if dy == 0 {
            return "Ты у самой стены магазина. Дверь прямо здесь. Открой ее и иди вправо."
        }
        if dy < 0 {
            return "Ты уперся в фасад продуктового. Дверь чуть впереди вдоль стены."
        }
        return "Ты уперся в фасад продуктового. Дверь чуть позади вдоль стены."
    }
}
