import Foundation

enum AudioCueID: String {
    case stepCarpet01
    case stepCarpet02
    case stepAsphalt01
    case stepAsphalt02
    case stepAsphalt03
    case stepAsphalt04
    case stepAsphalt05
    case ambientRoom01
    case cityStreetBed
    case obstacleThud
    case itemPlaceMetal01
    case glassBreakSmall
    case cabinetSmash
    case doorbellMain
    case doorBangingHard
    case doorBreakHeavy
    case gateOpen
    case gateClose
    case punchHit
    case heartbeatFast
    case kettleBasePlace
    case kettleSwitchOn
    case kettleHeatStart
    case kettleHeatLoop
    case kettleHeatFinish
    case trafficEngineBase
    case trafficBrakeSoft
    case trafficEngineLight
    case trafficEngineSedan
    case trafficEngineSport
    case trafficEngineCoupe
    case trafficEngineRoadster
    case playerCarDoorOpen
    case playerCarDoorClose
    case playerCarBrake
    case playerEngineLight
    case playerEngineSedan
    case playerEngineSport
    case playerEngineCoupe
    case playerStartLight
    case playerStartSedan
    case playerStartSport
    case playerStartCoupe
    case doorCloseBedroom
    case doorCloseLivingRoom
    case doorCloseKitchen
    case doorCloseBathroom
    case doorCloseTeaRoom
    case doorCloseHallway
    case doorOpenBedroom
    case doorOpenLivingRoom
    case doorOpenKitchen
    case doorOpenBathroom
    case doorOpenTeaRoom
    case doorOpenHallway
    case kettleLidOpen
    case kettleLidClose
    case kettlePlaceFloor
    case waterPour
    case bedLieDown
    case bedGetUp
    case pillowPickup
    case pillowDrop
    case pillowPlace
    case pillowSqueeze
    case pillowTear
    case doorBanging
    case fallSnow
    case humanFall1
    case humanFall2
    case neighborPunch
    case neighborStepClose
    case neighborStepHallway1
    case neighborStepHallway2
    case punchLight
    case neighborEntersBuilding
    case neighborExitsBuilding
    case neighborFootstepsBuilding

    var resourceName: String {
        switch self {
        case .stepCarpet01:
            return "step_carpet_01"
        case .stepCarpet02:
            return "step_carpet_02"
        case .stepAsphalt01:
            return "step_asphalt_01"
        case .stepAsphalt02:
            return "step_asphalt_02"
        case .stepAsphalt03:
            return "step_asphalt_03"
        case .stepAsphalt04:
            return "step_asphalt_04"
        case .stepAsphalt05:
            return "step_asphalt_05"
        case .ambientRoom01:
            return "ambient_room_01"
        case .cityStreetBed:
            return "city_street_bed"
        case .obstacleThud:
            return "item_place_metal_01"
        case .itemPlaceMetal01:
            return "item_place_metal_01"
        case .glassBreakSmall:
            return "glass_break_small"
        case .cabinetSmash:
            return "cabinet_smash"
        case .doorbellMain:
            return "doorbell_main"
        case .doorBangingHard:
            return "door_banging_hard"
        case .doorBreakHeavy:
            return "door_break_heavy"
        case .gateOpen:
            return "gate_open"
        case .gateClose:
            return "gate_close"
        case .punchHit:
            return "punch_hit"
        case .heartbeatFast:
            return "heartbeat_fast"
        case .kettleBasePlace:
            return "kettle_base_place_01"
        case .kettleSwitchOn:
            return "kettle_switch_on_01"
        case .kettleHeatStart:
            return "kettle_heat_start"
        case .kettleHeatLoop:
            return "kettle_heat_loop"
        case .kettleHeatFinish:
            return "kettle_heat_finish"
        case .trafficEngineBase:
            return "traffic_engine_base"
        case .trafficBrakeSoft:
            return "traffic_brake_soft"
        case .trafficEngineLight:
            return "traffic_engine_light"
        case .trafficEngineSedan:
            return "traffic_engine_sedan"
        case .trafficEngineSport:
            return "traffic_engine_sport"
        case .trafficEngineCoupe:
            return "traffic_engine_coupe"
        case .trafficEngineRoadster:
            return "traffic_engine_roadster"
        case .playerCarDoorOpen:
            return "car_door_open"
        case .playerCarDoorClose:
            return "car_door_close"
        case .playerCarBrake:
            return "player_car_brake"
        case .playerEngineLight:
            return "ts3_light_engine"
        case .playerEngineSedan:
            return "ts3_sedan_engine"
        case .playerEngineSport:
            return "ts3_sport_engine"
        case .playerEngineCoupe:
            return "ts3_coupe_engine"
        case .playerStartLight:
            return "ts3_start_light"
        case .playerStartSedan:
            return "ts3_start_common_b"
        case .playerStartSport:
            return "ts3_start_key"
        case .playerStartCoupe:
            return "ts3_start_coupe"
        case .doorCloseBedroom:
            return "door_close_bedroom"
        case .doorCloseLivingRoom:
            return "door_close_livingroom"
        case .doorCloseKitchen:
            return "door_close_kitchen"
        case .doorCloseBathroom:
            return "door_close_bathroom"
        case .doorCloseTeaRoom:
            return "door_close_tearoom"
        case .doorCloseHallway:
            return "door_close_hallway"
        case .doorOpenBedroom:
            return "door_open_bedroom"
        case .doorOpenLivingRoom:
            return "door_open_livingroom"
        case .doorOpenKitchen:
            return "door_open_kitchen"
        case .doorOpenBathroom:
            return "door_open_bathroom"
        case .doorOpenTeaRoom:
            return "door_open_tearoom"
        case .doorOpenHallway:
            return "door_open_hallway"
        case .kettleLidOpen:
            return "kettle_lid_open"
        case .kettleLidClose:
            return "kettle_lid_close"
        case .kettlePlaceFloor:
            return "kettle_place_floor"
        case .waterPour:
            return "water_pour"
        case .bedLieDown:
            return "bed_lie_down"
        case .bedGetUp:
            return "bed_get_up"
        case .pillowPickup:
            return "pillow_pickup"
        case .pillowDrop:
            return "pillow_drop"
        case .pillowPlace:
            return "pillow_place"
        case .pillowSqueeze:
            return "pillow_squeeze"
        case .pillowTear:
            return "pillow_tear"
        case .doorBanging:
            return "door_banging"
        case .fallSnow:
            return "fall_snow"
        case .humanFall1:
            return "humanFall1"
        case .humanFall2:
            return "humanFall2"
        case .neighborPunch:
            return "neighbor_punch"
        case .neighborStepClose:
            return "neighbor_step_close"
        case .neighborStepHallway1:
            return "neighbor_step_hallway1"
        case .neighborStepHallway2:
            return "neighbor_step_hallway2"
        case .punchLight:
            return "punch_light"
        case .neighborEntersBuilding:
            return "neighbor_enters_building"
        case .neighborExitsBuilding:
            return "neighbor_exits_building"
        case .neighborFootstepsBuilding:
            return "neighbor_footsteps_building"
        }
    }

    var fileExtension: String {
        switch self {
        case .stepCarpet01, .stepCarpet02, .stepAsphalt01, .stepAsphalt02, .stepAsphalt03, .stepAsphalt04, .stepAsphalt05, .ambientRoom01, .cityStreetBed, .kettleBasePlace, .kettleSwitchOn:
            return "mp3"
        case .obstacleThud, .itemPlaceMetal01:
            return "m4a"
        case .playerCarDoorOpen, .playerCarDoorClose:
            return "mp3"
        case .glassBreakSmall, .cabinetSmash, .doorbellMain, .doorBangingHard, .doorBreakHeavy, .gateOpen, .gateClose, .punchHit, .heartbeatFast, .kettleHeatStart, .kettleHeatLoop, .kettleHeatFinish, .trafficEngineBase, .trafficBrakeSoft, .trafficEngineLight, .trafficEngineSedan, .trafficEngineSport, .trafficEngineCoupe, .trafficEngineRoadster, .playerCarBrake, .playerEngineLight, .playerEngineSedan, .playerEngineSport, .playerEngineCoupe, .playerStartLight, .playerStartSedan, .playerStartSport, .playerStartCoupe:
            return "wav"
        case .doorCloseBedroom, .doorCloseLivingRoom, .doorCloseKitchen, .doorCloseBathroom, .doorCloseTeaRoom, .doorCloseHallway, .doorOpenBedroom, .doorOpenLivingRoom, .doorOpenKitchen, .doorOpenBathroom, .doorOpenTeaRoom, .doorOpenHallway, .kettleLidOpen, .kettleLidClose, .kettlePlaceFloor, .waterPour, .bedLieDown, .bedGetUp, .pillowPickup, .pillowDrop, .pillowPlace, .pillowSqueeze, .pillowTear:
            return "mp3"
        case .neighborStepHallway1, .neighborStepHallway2, .neighborStepClose, .neighborPunch, .punchLight, .doorBanging, .fallSnow:
            return "wav"
        case .neighborEntersBuilding, .neighborExitsBuilding, .neighborFootstepsBuilding:
            return "wav"
        case .humanFall1, .humanFall2:
            return "mp3"
        }
    }

    var defaultVolume: Float {
        switch self {
        case .ambientRoom01:
            return 0.2
        case .stepCarpet01, .stepCarpet02:
            return 0.6
        case .stepAsphalt01, .stepAsphalt02, .stepAsphalt03, .stepAsphalt04, .stepAsphalt05:
            return 0.78
        case .cityStreetBed:
            return 0.24
        case .obstacleThud:
            return 0.55
        case .itemPlaceMetal01:
            return 0.75
        case .glassBreakSmall:
            return 0.9
        case .cabinetSmash:
            return 0.95
        case .doorbellMain:
            return 0.55
        case .doorBangingHard:
            return 0.72
        case .doorBreakHeavy:
            return 1.08
        case .gateOpen:
            return 0.86
        case .gateClose:
            return 0.84
        case .punchHit:
            return 0.82
        case .heartbeatFast:
            return 0.34
        case .kettleBasePlace:
            return 0.82
        case .kettleSwitchOn:
            return 0.72
        case .kettleHeatStart:
            return 0.44
        case .kettleHeatLoop:
            return 0.28
        case .kettleHeatFinish:
            return 0.38
        case .trafficEngineBase:
            return 0.44
        case .trafficBrakeSoft:
            return 0.26
        case .trafficEngineLight:
            return 0.48
        case .trafficEngineSedan:
            return 0.46
        case .trafficEngineSport:
            return 0.4
        case .trafficEngineCoupe:
            return 0.43
        case .trafficEngineRoadster:
            return 0.41
        case .playerCarDoorOpen:
            return 0.82
        case .playerCarDoorClose:
            return 0.88
        case .playerCarBrake:
            return 0.68
        case .playerEngineLight:
            return 0.82
        case .playerEngineSedan:
            return 0.84
        case .playerEngineSport:
            return 0.8
        case .playerEngineCoupe:
            return 0.82
        case .playerStartLight:
            return 0.92
        case .playerStartSedan:
            return 0.95
        case .playerStartSport:
            return 0.95
        case .playerStartCoupe:
            return 0.95
        case .doorCloseBedroom, .doorCloseLivingRoom, .doorCloseKitchen, .doorCloseBathroom, .doorCloseTeaRoom, .doorCloseHallway:
            return 0.7
        case .doorOpenBedroom, .doorOpenLivingRoom, .doorOpenKitchen, .doorOpenBathroom, .doorOpenTeaRoom, .doorOpenHallway:
            return 0.65
        case .kettleLidOpen, .kettleLidClose:
            return 0.6
        case .kettlePlaceFloor:
            return 0.7
        case .waterPour:
            return 0.7
        case .bedLieDown, .bedGetUp:
            return 0.5
        case .pillowPickup, .pillowDrop, .pillowPlace:
            return 0.4
        case .pillowSqueeze, .pillowTear:
            return 0.35
        case .neighborStepHallway1, .neighborStepHallway2:
            return 0.7
        case .neighborStepClose:
            return 0.75
        case .neighborPunch:
            return 0.85
        case .punchLight:
            return 0.65
        case .doorBanging:
            return 0.8
        case .fallSnow:
            return 0.7
        case .humanFall1, .humanFall2:
            return 0.7
        case .neighborEntersBuilding, .neighborExitsBuilding:
            return 0.7
        case .neighborFootstepsBuilding:
            return 0.65
        }
    }

    var loops: Bool {
        self == .ambientRoom01 || self == .heartbeatFast || self == .cityStreetBed || self == .kettleHeatLoop
    }
}
