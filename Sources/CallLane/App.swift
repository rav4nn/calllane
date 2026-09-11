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
