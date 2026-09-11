import SwiftUI
import CoreAudio

struct MenuView: View {
    @Bindable var controller: Controller
    @Bindable var loginItem: LoginItem
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("Output") {
                ForEach(controller.outputs) { d in
                    deviceRow(d, selected: d.id == controller.defaultOutputID) { controller.selectOutput(d.id) }
                }
                if let v = controller.outputVolume {
                    Slider(value: Binding(get: { v }, set: { controller.setOutputVolume($0) }), in: 0...1) {
                        Image(systemName: "speaker.wave.2")
                    }
                } else {
                    Text("This output has no volume control.").font(.caption).foregroundStyle(.secondary)
                }
            }

            section("Input") {
                ForEach(controller.inputs) { d in
                    deviceRow(d, selected: d.id == controller.defaultInputID) { controller.selectInput(d.id) }
                }
                Toggle("Lock input", isOn: $controller.inputLocked).toggleStyle(.switch).controlSize(.small)
            }

            section("Calls device") {
                HStack(spacing: 6) {
                    Circle().fill(controller.callsInUse ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                    Text("Calls → \(controller.callsWraps?.name ?? "no output") · \(controller.callsInUse ? "in use" : "idle")")
                }
                if !controller.status.isEmpty {
                    Text(controller.status).font(.caption).foregroundStyle(.orange)
                }
                Text("Select “Calls” as the speaker inside each call app.").font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            Button("Setup guide…") { openWindow(id: "setup"); NSApp.activate(ignoringOtherApps: true) }
            Toggle("Launch at login", isOn: $loginItem.enabled)
            if !loginItem.error.isEmpty {
                Text(loginItem.error).font(.caption).foregroundStyle(.orange)
            }
            Button("Remove Calls device and quit") {
                if controller.removeCallsDevice() { NSApp.terminate(nil) }
            }
            Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { controller.reconcile() }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func deviceRow(_ d: AudioDevice, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "checkmark").opacity(selected ? 1 : 0).frame(width: 12)
                Text(d.name).lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
