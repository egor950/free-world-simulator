import Foundation
import SwiftUI

/// UI-состояние игры: тексты, заголовки, меню, инвентарь.
/// Отдельный ObservableObject для привязки к SwiftUI через @ObservedObject.
@MainActor
final class GameUIState: ObservableObject {
    @Published var stage: GameStage = .welcome
    @Published var selectedCharacterKind: CharacterKind = .man
    @Published var characterName: String = ""

    @Published var statusText: String = ""
    @Published var roomTitle: String = ""
    @Published var focusTitle: String = ""
    @Published var focusShortText: String = ""
    @Published var holdText: String = ""
    @Published var eventLog: [String] = []
    @Published var tutorialText: String = ""
    @Published var isTutorialVisible: Bool = false
    @Published var isInventoryOpen: Bool = false
    @Published var inventoryTitle: String = ""
    @Published var inventoryText: String = ""
    @Published var isLocationMenuOpen: Bool = false
    @Published var locationMenuTitle: String = ""
    @Published var locationMenuText: String = ""

    init() {
        self.statusText = """
        Добро пожаловать в игру «Симулятор свободного мира».
        Здесь мы исследуем квартиру, подходим к дверям и предметам, а длинные описания слушаем отдельно.
        """
    }
}
