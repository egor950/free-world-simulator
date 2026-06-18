import Foundation

extension GameViewModel {
    func updateDrivingHint(currentCar: ControlledCarState, previousSpeed: Double) {
        let cameToStop = abs(currentCar.speed) <= 0.05 && abs(previousSpeed) > 0.55

        if currentCar.engineState != .running {
            if currentCar.phase == .parked {
                announceDrivingHintIfNeeded("Мотор заглушен. Нажми E, чтобы завести машину.", minimumGap: 2.2)
            }
            return
        }

        if currentCar.roomID == .street, currentCar.worldPosition.z > 15.6 {
            let gateIsOpen = currentGateIsOpen()
            if !gateIsOpen && cameToStop {
                announceDrivingHintIfNeeded("Перед тобой калитка. Остановись, выйди и открой её пешком.")
                return
            }
            if gateIsOpen && shouldAutoPassGate(for: currentCar) {
                announceDrivingHintIfNeeded("Калитка открыта. Просто держись прямо, машина сама пройдёт через проём.", minimumGap: 1.4)
                return
            }
            if gateIsOpen && currentCar.worldPosition.z >= 16.5 && abs(currentCar.worldPosition.x) > 10.5 && cameToStop {
                announceDrivingHintIfNeeded("Калитка уже открыта, но машина смещена. Вернись ближе к центру проезда.", minimumGap: 1.3)
                return
            }
            if gateIsOpen && currentCar.worldPosition.z >= 18.0 && currentCar.worldPosition.z < 23.5 {
                announceDrivingHintIfNeeded("Калитка открыта. Теперь держись прямо и выезжай на большую улицу.", minimumGap: 1.6)
                return
            }
        }

        if currentCar.roomID == .street,
           currentCar.worldPosition.z >= 9.0,
           currentCar.worldPosition.z < 15.6,
           currentCar.speed > 0.6 {
            announceDrivingHintIfNeeded("Калитка уже впереди. Просто держись прямо.", minimumGap: 1.8)
            return
        }

        if currentCar.roomID == .street, cameToStop {
            if currentCar.worldPosition.x <= -33.9 {
                announceDrivingHintIfNeeded("Слева стена дома. Дальше машина не пройдёт.")
                return
            }
            if currentCar.worldPosition.x >= 33.9 {
                announceDrivingHintIfNeeded("Справа край двора. Дальше машина не пройдёт.")
                return
            }
            if currentCar.worldPosition.z <= -17.4 {
                announceDrivingHintIfNeeded("Позади край двора. Дальше машины не проходит.")
                return
            }
        }

        if currentCar.roomID == .mainStreet {
            let storeZ: Float = 30.25
            if currentCar.worldPosition.z < storeZ - 5.5 {
                announceDrivingHintIfNeeded("Едь прямо по большой улице и держись по центру. До продуктового ещё есть путь.", minimumGap: 2.3)
                return
            }

            if currentCar.worldPosition.z <= storeZ + 5 {
                if currentCar.worldPosition.x < 12 {
                    announceDrivingHintIfNeeded("Ты поравнялся с магазином. Теперь начинай плавно уходить вправо.", minimumGap: 1.9)
                    return
                }
                if currentCar.worldPosition.x < 32 {
                    announceDrivingHintIfNeeded("Поворот правильный. Продолжай плавно держаться правее.", minimumGap: 1.8)
                    return
                }
                if currentCar.worldPosition.x < 56 {
                    announceDrivingHintIfNeeded("Хорошо. Ещё немного правее к парковке продуктового.", minimumGap: 1.6)
                    return
                }
                if currentCar.worldPosition.x <= 76 {
                    announceDrivingHintIfNeeded("Ты уже в точке парковки у входа продуктового. Дальше вправо не нужно, можно останавливаться и выходить.", minimumGap: 1.8)
                    return
                }
            }

            if cameToStop {
                if currentCar.worldPosition.x <= -89.9 {
                    announceDrivingHintIfNeeded("Слева край большой улицы. Дальше машина не пройдёт.")
                    return
                }
                if currentCar.worldPosition.x >= 89.9 {
                    announceDrivingHintIfNeeded("Справа край большой улицы. Дальше машина не пройдёт.")
                    return
                }
                if currentCar.worldPosition.z <= 23.55 {
                    announceDrivingHintIfNeeded("Позади снова двор и калитка. Дальше назад машина не прошла.")
                    return
                }
                if currentCar.worldPosition.z >= 53.45 {
                    announceDrivingHintIfNeeded("Впереди край большой улицы. Дальше пока не проехать.")
                    return
                }
            }
        }
    }
}
