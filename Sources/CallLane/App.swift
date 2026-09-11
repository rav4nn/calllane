import SwiftUI
import ServiceManagement
import Observation

// No @State anywhere: the macOS 27 SDK makes @State a macro whose plugin ships only with Xcode.
// The app struct is created once, so plain stored properties are enough.

@main
struct CallLaneApp: App {
    private let controller: Controller
    private let loginItem = LoginItem()

    init() {
        controller = Controller(audio: CoreAudioSystem())
        controller.start()
        // `scripts/snap.sh` screenshots this window: the menu bar popover cannot be captured.
        if CommandLine.arguments.contains("--preview") { showPreviewWindow() }
    }

    private func showPreviewWindow() {
        let controller = self.controller
        let loginItem = self.loginItem
        DispatchQueue.main.async {
            let host = NSHostingView(rootView: MenuView(controller: controller, loginItem: loginItem))
            host.frame.size = host.fittingSize
            let window = NSWindow(contentRect: host.frame,
                                  styleMask: [.titled, .closable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "CallLane Panel Preview"
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.center()
            PreviewWindow.shared = window
            // Writing AppleInterfaceStyle does not reach an already-running session, so the
            // screenshot script asks for the appearance it wants directly.
            if CommandLine.arguments.contains("--dark") {
                NSApp.appearance = NSAppearance(named: .darkAqua)
            } else if CommandLine.arguments.contains("--light") {
                NSApp.appearance = NSAppearance(named: .aqua)
            }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller, loginItem: loginItem)
        } label: {
            Image(systemName: controller.callsInUse ? "phone.circle.fill" : "phone.circle")
        }
        .menuBarExtraStyle(.window)

        Window("CallLane Setup", id: "setup") {
            SetupView()
        }
        .windowResizability(.contentSize)
    }
}

/// Keeps the `--preview` window alive for the life of the process.
@MainActor
enum PreviewWindow {
    static var shared: NSWindow?
}

@Observable
final class LoginItem {
    private(set) var error = ""
    var enabled: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            let registered = SMAppService.mainApp.status == .enabled
            guard enabled != registered else { return }
            do {
                enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister()
                error = ""
            } catch {
                self.error = "Launch at login failed: \(error.localizedDescription)"
                log.error("launch at login: \(String(describing: error))")
            }
            // The service is the source of truth; a failed call leaves the toggle where it was.
            enabled = SMAppService.mainApp.status == .enabled
        }
    }
}
