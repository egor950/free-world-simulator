import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct FreeWorldMacApp: App {
    @StateObject private var viewModel: GameViewModel
    private let embeddedMCPEnabled: Bool

    @MainActor
    init() {
        let env = ProcessInfo.processInfo.environment
        embeddedMCPEnabled = env["FREEWORLD_EMBEDDED_MCP"] == "1"
        #if os(macOS)
        if embeddedMCPEnabled {
            NSApplication.shared.setActivationPolicy(.prohibited)
        }
        #endif
        _viewModel = StateObject(wrappedValue: LiveGameBridge.shared.makeViewModel {
            #if os(macOS)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                NSApp.terminate(nil)
            }
            #endif
        })

        if embeddedMCPEnabled {
            let server = StdioMCPServer(runtime: EmbeddedGameRuntime())
            Thread.detachNewThread {
                server.run()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if embeddedMCPEnabled {
                EmptyView()
            } else {
                RootGameView(viewModel: viewModel)
            }
        }
    }
}
