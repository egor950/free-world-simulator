import Foundation

/// Состояние навигационного маяка: текущая цель, индекс в меню, активная задача.
@MainActor
final class NavigationBeaconState {
    var activeNavigationBeaconID: String?
    var selectedLocationMenuIndex: Int = 0
    var navigationBeaconTask: Task<Void, Never>?
}
