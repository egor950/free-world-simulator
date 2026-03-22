import SwiftUI

@main
struct FreeWorldIOSApp: App {
    @StateObject private var viewModel = GameViewModel()

    var body: some Scene {
        WindowGroup {
            RootGameView(viewModel: viewModel)
        }
    }
}
