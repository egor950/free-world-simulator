import SwiftUI
#if os(macOS)
import AppKit

final class FreeWorldAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.bringWindowToFront()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.setActivationPolicy(.regular)
        sender.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.bringWindowToFront()
        }
        return true
    }

    private func bringWindowToFront() {
        guard let window = NSApp.windows.first else { return }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}
#endif

@main
struct FreeWorldMacApp: App {
    @StateObject private var viewModel: GameViewModel
    #if os(macOS)
    @NSApplicationDelegateAdaptor(FreeWorldAppDelegate.self) private var appDelegate
    #endif

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
