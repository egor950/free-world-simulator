# Vehicles Module

Система машин: вождение, парковка, звуки двигателя.

## STRUCTURE
```
Vehicles/
├── GameViewModel+VehicleActions.swift    # Действия с машинами (273 строки)
├── GameViewModel+VehicleDriving.swift    # Вождение (584 строки)
├── GameViewModel+VehicleWorld.swift      # Мир машин (340 строк)
├── AudioCoordinator+PlayerCar.swift      # Звук игрока (333 строки)
├── AudioCoordinator+ParkedOwnedCars.swift # Звук припаркованных
├── AudioCoordinator+DriveableCars.swift  # Звук движущихся
├── CarLifecycleMachine.swift            # FSM для жизненного цикла
├── GameVehicleRuntime.swift             # Runtime состояние
└── VehicleWorldModels.swift             # Модели данных
```

## KEY TYPES
- `DriveableVehicleKind` — light/sedan/sport/coupe/roadster
- `ControlledCarState` — состояние управляемой машины
- `ParkedOwnedCarState` — припаркованная машина игрока
- `CarLifecycleMachine` — GKStateMachine для phase переходов
- `ControlledCarPhase` — onFoot → entering → driving → exiting

## PATTERNS
- Вождение работает через `speed` + `steeringAxis`
- Звук двигателя = pitch от `idleEngineHz` до `maxEngineHz`
- Фазы жизни машины через `CarLifecycleMachine` (GKStateMachine)

## ANTI-PATTERNS
- **НЕЛЬЗЯ** менять `DriveableVehicleBlueprint` без понимания влияния на звук
- **НЕЛЬЗЯ** добавлять новые фазы без валидации в `isValidNextState`
