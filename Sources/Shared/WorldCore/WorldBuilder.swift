import Foundation

enum WorldBuilder {
    static func makeWorld() -> [RoomID: RoomDefinition] {
        let rooms = [
            HallwayRoom.make(),
            BedroomRoom.make(),
            LivingRoomRoom.make(),
            KitchenRoom.make(),
            BathroomRoom.make(),
            StreetRoom.make(),
            MainStreetRoom.make()
        ]

        return Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
    }
}
