import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct FreeWorldMacApp: App {
    @StateObject private var viewModel: GameViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: LiveGameBridge.shared.makeViewModel {
            #if os(macOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                NSApp.terminate(nil)
            }
            #endif
        })
    }

    var body: some Scene {
        WindowGroup {
            RootGameView(viewModel: viewModel)
        }
    }
}
