import Foundation

struct DriveableCarContext {
    let id: UUID
    let title: String
    let kind: DriveableVehicleKind
    let worldPosition: OutdoorCarWorldPosition
    let gridPosition: GridPosition
    let directionLeftToRight: Bool
    let isOwned: Bool
    let isEngineRunning: Bool
}

extension GameViewModel {
    func currentFocusDriveableCarContext() -> DriveableCarContext? {
        if let node = currentFocusNode,
           node.id.hasPrefix("dynamic.ownedCar."),
           let uuid = UUID(uuidString: String(node.id.dropFirst("dynamic.ownedCar.".count))),
           let ownedCar = state.parkedOwnedCars[uuid] {
            return DriveableCarContext(
                id: ownedCar.id,
                title: ownedCar.title,
                kind: ownedCar.kind,
                worldPosition: ownedCar.worldPosition,
                gridPosition: ownedCar.gridPosition,
                directionLeftToRight: ownedCar.directionLeftToRight,
                isOwned: true,
                isEngineRunning: ownedCar.isEngineRunning
            )
        }

        if let snapshot = currentFocusStreetCarSnapshot(), snapshot.isParked {
            return DriveableCarContext(
                id: snapshot.id,
                title: snapshot.title,
                kind: snapshot.vehicleKind,
                worldPosition: snapshot.worldPosition,
                gridPosition: snapshot.position,
                directionLeftToRight: snapshot.directionLeftToRight,
                isOwned: false,
                isEngineRunning: false
            )
        }

        return nil
    }

    func nearbyOwnedParkedCarNode(maxDistance: Int) -> FocusNode? {
        guard currentRoom.id == .street || currentRoom.id == .mainStreet else {
            return nil
        }

        let playerPosition = state.player.roomPosition
        guard let nearest = state.parkedOwnedCars.values
            .filter({ $0.roomID == currentRoom.id })
            .min(by: {
                manhattanDistance(from: $0.gridPosition, to: playerPosition) <
                manhattanDistance(from: $1.gridPosition, to: playerPosition)
            }) else {
            return nil
        }

        let distance = manhattanDistance(from: nearest.gridPosition, to: playerPosition)
        guard distance <= maxDistance else {
            return nil
        }

        return FocusNode(
            id: "dynamic.ownedCar.\(nearest.id.uuidString)",
            title: nearest.title,
            position: nearest.gridPosition,
            target: .none,
            shortPrompt: parkedOwnedCarShortPrompt(nearest),
            fullDescription: parkedOwnedCarFullDescription(nearest)
        )
    }

    func nearestDriveableCarContext(maxDistance: Int) -> DriveableCarContext? {
        guard state.controlledCar == nil else {
            return nil
        }

        if currentRoom.id == .street || currentRoom.id == .mainStreet {
            let playerPosition = state.player.roomPosition
            if let nearestOwned = state.parkedOwnedCars.values
                .filter({ $0.roomID == currentRoom.id })
                .min(by: {
                    manhattanDistance(from: $0.gridPosition, to: playerPosition) <
                    manhattanDistance(from: $1.gridPosition, to: playerPosition)
                }) {
                let distance = manhattanDistance(from: nearestOwned.gridPosition, to: playerPosition)
                if distance <= maxDistance {
                    return DriveableCarContext(
                        id: nearestOwned.id,
                        title: nearestOwned.title,
                        kind: nearestOwned.kind,
                        worldPosition: nearestOwned.worldPosition,
                        gridPosition: nearestOwned.gridPosition,
                        directionLeftToRight: nearestOwned.directionLeftToRight,
                        isOwned: true,
                        isEngineRunning: nearestOwned.isEngineRunning
                    )
                }
            }
        }

        if let snapshot = nearestParkedStreetCarSnapshot(maxDistance: maxDistance) {
            return DriveableCarContext(
                id: snapshot.id,
                title: snapshot.title,
                kind: snapshot.vehicleKind,
                worldPosition: snapshot.worldPosition,
                gridPosition: snapshot.position,
                directionLeftToRight: snapshot.directionLeftToRight,
                isOwned: false,
                isEngineRunning: true
            )
        }

        return nil
    }

    func driveableCarShortPrompt(_ context: DriveableCarContext) -> String {
        if context.kind == .roadster {
            return "Рядом \(context.title). В него пока нельзя сесть."
        }
        if !context.isOwned {
            return "Рядом \(context.title). Нажми E, чтобы сесть. Потом ещё раз E заведет мотор."
        }
        if context.isOwned && context.isEngineRunning {
            return "Рядом \(context.title). Мотор уже работает. Нажми E, чтобы снова сесть."
        }
        return "Рядом \(context.title). Нажми E, чтобы сесть."
    }

    func parkedOwnedCarShortPrompt(_ car: ParkedOwnedCarState) -> String {
        if car.isEngineRunning {
            return "Рядом \(car.title). Мотор мягко урчит. Нажми E, чтобы сесть."
        }
        return "Рядом \(car.title). Нажми E, чтобы сесть."
    }

    func parkedOwnedCarFullDescription(_ car: ParkedOwnedCarState) -> String {
        let engineText = car.isEngineRunning
            ? "Мотор оставлен заведенным и мягко урчит."
            : "Мотор сейчас молчит."
        return "Перед тобой \(car.title). Она стоит там, где ты её оставил. \(engineText)"
    }

    func controlledCarShortPrompt(_ car: ControlledCarState) -> String {
        let speedText = Int(abs(car.speed) * 3.6)
        switch car.phase {
        case .carDoorOpeningForEnter:
            return "Ты открыл дверь машины и сейчас садишься."
        case .enteringVehicle:
            return "Ты залезаешь в машину."
        case .carDoorClosingAfterEnter:
            return "Ты сел в машину. Дверь закрывается."
        case .engineStarting:
            return "Ты уже в машине. Идёт заводка."
        case .engineIdle:
            return "Ты за рулем \(car.title). Машина стоит. Скорость \(speedText) километров в час."
        case .parked:
            if car.engineState == .running {
                return "Ты за рулем \(car.title). Машина стоит. Скорость \(speedText) километров в час."
            }
            return "Ты за рулем \(car.title). Мотор заглушен. Нажми E, чтобы завести."
        case .carDoorOpeningForExit:
            return "Ты остановил машину. Дверь открывается."
        case .exitingVehicle:
            return "Ты вылезаешь из машины."
        case .carDoorClosingAfterExit:
            return "Ты уже вышел. Дверь закрывается."
        default:
            return "Ты за рулем \(car.title). Скорость \(speedText) километров в час."
        }
    }

    func controlledCarFullDescription(_ car: ControlledCarState) -> String {
        "\(controlledCarStatusText(car)) Выйти можно только после полной остановки."
    }

    func controlledCarStatusText(_ car: ControlledCarState) -> String {
        switch car.phase {
        case .carDoorOpeningForEnter:
            return "Ты открыл дверь машины и сейчас садишься."
        case .enteringVehicle:
            return "Ты уже залезаешь в машину."
        case .carDoorClosingAfterEnter:
            return "Ты сел в машину. Дверь закрывается."
        case .engineStarting:
            return "Ты сидишь в машине. Идёт заводка мотора."
        case .carDoorOpeningForExit:
            return "Ты остановил машину. Дверь открывается."
        case .exitingVehicle:
            return "Ты вылезаешь из машины."
        case .carDoorClosingAfterExit:
            return "Ты уже вышел. Дверь закрывается."
        case .engineIdle, .driving, .onFoot:
            break
        case .parked:
            if car.engineState != .running {
                return "Ты сидишь в \(car.title). Мотор заглушен. Нажми E, чтобы завести."
            }
        }

        let speedText = Int(abs(car.speed) * 3.6)

        if car.roomID == .street {
            let gateOpen = currentGateIsOpen()
            if car.worldPosition.z < 8 {
                return "Ты за рулем \(car.title) во дворе. Скорость \(speedText) километров в час. Калитка дальше впереди."
            }

            if car.worldPosition.z < 16.6 {
                return "Ты едешь по двору к калитке. Скорость \(speedText) километров в час. Держись прямо."
            }

            if !gateOpen {
                return "Перед машиной закрытая калитка. Скорость \(speedText) километров в час. Остановись, выйди и открой её пешком."
            }

            if abs(car.worldPosition.x) > 10 {
                return "Калитка открыта, но машина смещена. Скорость \(speedText) километров в час. Вернись ближе к центру проезда."
            }

            return "Ты проходишь через калитку. Скорость \(speedText) километров в час. Держись прямо на большую улицу."
        }

        if car.roomID == .mainStreet {
            let storeZ: Float = 30.25
            if car.worldPosition.z < storeZ - 4.5 {
                return "Ты едешь по большой улице. Скорость \(speedText) километров в час. Продуктовый дальше впереди справа."
            }

            if currentGateIsOpen() && car.worldPosition.z <= 25 {
                return "Ты только выехал на большую улицу. Скорость \(speedText) километров в час. Держись вперёд к магазину."
            }

            if currentCarNearStoreBand(car) {
                if car.worldPosition.x < 30 {
                    return "Ты уже на уровне продуктового. Скорость \(speedText) километров в час. Плавно держись правее к парковке."
                }
                if car.worldPosition.x < 54 {
                    return "Ты почти у парковки продуктового. Скорость \(speedText) километров в час. Ещё немного правее."
                }
                return "Ты у парковки продуктового. Скорость \(speedText) километров в час."
            }

            if car.worldPosition.z >= 53.4 {
                return "Перед машиной край большой улицы. Скорость \(speedText) километров в час. Дальше пока не проехать."
            }

            return "Ты едешь по большой улице. Скорость \(speedText) километров в час."
        }

        return "Ты за рулем \(car.title). Скорость \(speedText) километров в час."
    }

    func currentCarNearStoreBand(_ car: ControlledCarState) -> Bool {
        let storeZ: Float = 30.25
        return car.worldPosition.z >= storeZ - 2.5 && car.worldPosition.z <= storeZ + 6.5
    }

    func worldRoomID(for point: OutdoorCarWorldPosition) -> RoomID {
        point.z < 20.5 ? .street : .mainStreet
    }

    func initialHeadingRadians(
        for point: OutdoorCarWorldPosition,
        roomID: RoomID,
        directionLeftToRight: Bool
    ) -> Double {
        switch roomID {
        case .mainStreet:
            return directionLeftToRight ? (.pi / 2) : (-.pi / 2)
        case .street:
            return point.z < 20.5 ? 0 : (directionLeftToRight ? (.pi / 2) : (-.pi / 2))
        default:
            return 0
        }
    }

    func gridPosition(for point: OutdoorCarWorldPosition, roomID: RoomID) -> GridPosition {
        switch roomID {
        case .street:
            let gridX = Int(round(((point.x + 34) / 68) * 14))
            let gridY = Int(round(7 - (point.z / 2.5)))
            return GridPosition(
                x: min(14, max(0, gridX)),
                y: min(14, max(0, gridY))
            )
        case .mainStreet:
            let gridX = Int(round(((point.x + 90) / 180) * Float(MainStreetRoom.width - 1)))
            let normalizedZ = (point.z - 23.5) / 30.0
            let gridY = Int(round(Float(MainStreetRoom.height - 1) - normalizedZ * Float(MainStreetRoom.height - 1)))
            return GridPosition(
                x: min(MainStreetRoom.width - 1, max(0, gridX)),
                y: min(MainStreetRoom.height - 1, max(0, gridY))
            )
        default:
            return state.player.roomPosition
        }
    }
}
