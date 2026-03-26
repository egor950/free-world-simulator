import Foundation

extension AudioCoordinator {
    func ensureDriveableCourtyardCar() {
        streetTraffic?.ensureDriveableCourtyardCar()
    }

    func claimParkedCar(id: UUID) -> StreetTrafficCoordinator.StreetCarSnapshot? {
        streetTraffic?.claimParkedCar(id: id)
    }
}
