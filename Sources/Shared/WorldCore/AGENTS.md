# WorldCore Module

Ядро мира: модели данных, сборка комнат, состояния.

## STRUCTURE
```
WorldCore/
├── WorldModels.swift      # Все модели (841 строка)
├── WorldBuilder.swift     # Сборка мира (21 строка)
├── FlowController.swift   # FSM для этапов игры
├── StreetRoom.swift       # Двор
└── MainStreetRoom.swift   # Главная улица
```

## KEY TYPES
- `GameStage` — welcome/characterCreation/exploration/finished
- `RoomID` — enum всех комнат (hallway, bedroom, kitchen, etc.)
- `WorldRuntimeState` — полное состояние мира
- `PlayerState` — комната, позиция, поза, предмет в руках
- `RoomDefinition` — определение комнаты (узлы, двери, предметы)
- `ItemDefinition` — определение предмета (описание, действия)
- `ItemAction` — действие с предметом (триггер, текст, звук, мутация)
- `AudioCueID` — enum всех звуков (100+ cases)

## PATTERNS
- `enum + static func make()` — каждый тип определён как enum
- `ItemDefinition.actionsProvider: (WorldRuntimeState) -> [ItemAction]` — замыкание
- `stateMutation: (inout WorldRuntimeState) -> Void` — мутация состояния

## ANTI-PATTERNS
- **НЕЛЬЗЯ** добавлять логику в WorldModels.swift — только модели данных
- **НЕЛЬЗЯ** изменять `ItemAction` signature без обновления всех предметов
