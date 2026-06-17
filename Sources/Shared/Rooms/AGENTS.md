# Rooms Module

Комнаты и предметы: определения, взаимодействия, звуки.

## STRUCTURE
```
Rooms/
├── ApartmentItems/     # Предметы квартиры (4 файла)
│   ├── BathroomFaucet.swift  # Кран (наливание воды)
│   ├── KitchenKettle.swift   # Чайник (крышка, вода, нагрев)
│   ├── KitchenMug.swift      # Кружка (заливание, продажа)
│   └── KitchenStove.swift    # Подставка (нагрев чайника)
├── Bathroom/           # Ванная (2 файла)
│   ├── BathroomRoom.swift
│   └── Mirror.swift          # Зеркало (можно разбить)
├── Bedroom/            # Спальня (3 файла)
│   ├── BedroomRoom.swift
│   ├── Bed.swift             # Кровать (лечь/встать)
│   └── Pillow.swift          # Подушка (взять/смять/порвать)
├── GroceryStore/       # Продуктовый (3 файла)
│   ├── GroceryStoreRoom.swift
│   ├── GroceryStoreTeabag.swift  # Пакетик чая
│   └── GroceryStoreSugar.swift   # Пакетик сахара
├── Hallway/            # Прихожая (3 файла)
│   ├── HallwayRoom.swift
│   ├── CoatRack.swift        # Вешалка
│   └── TeaShop.swift         # Стойка чайного бизнеса
├── Kitchen/            # Кухня (2 файла)
│   ├── KitchenRoom.swift
│   └── Fridge.swift          # Холодильник (можно разбить)
├── LivingRoom/         # Гостиная (2 файла)
│   ├── LivingRoomRoom.swift
│   └── Table.swift           # Стол (можно разбить)
└── TeaRoom/            # Чайная (2 файла)
    ├── TeaRoom.swift
    └── TeaRoomTable.swift    # Столик для чая (заваривание)
```

## PATTERNS
- Каждая комната: `enum XxxRoom { static func make() -> RoomDefinition }`
- Каждый предмет: `enum XxxItem { static func make() -> ItemDefinition }`
- Предметы с состоянием используют `WorldRuntimeState.itemStage()`
- Двери: `DoorDefinition` с `targetRoomID`, `targetRoomPosition`

## KEY INTERACTIONS
- Чайник → подставка → нагрев → кипяток
- Кружка + кипяток → столик + пакетик чая → заваривание → продажа
- Подушка: взять → смять → порвать (состояния: intact/dusty/torn)
- Зеркало, стол, холодильник: можно разбить (intact/broken)

## ANTI-PATTERNS
- **НЕЛЬЗЯ** объединять несколько предметов в один файл
- **НЕЛЬЗЯ** дублировать `heldActions` между предметами
- **НЕЛЬЗЯ** использовать hardcoded позиции — только через `GridPosition`
