import Foundation

enum WorldBuilder {
    static func makeWorld() -> [RoomID: RoomDefinition] {
        let rooms = [
            HallwayRoom.make(),
            BedroomRoom.make(),
            LivingRoomRoom.make(),
            KitchenRoom.make(),
            BathroomRoom.make(),
            TeaRoom.make(),
            StreetRoom.make(),
            MainStreetRoom.make(),
            GroceryStoreRoom.make()
        ]

        return Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
    }
}
