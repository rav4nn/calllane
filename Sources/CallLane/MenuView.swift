import SwiftUI
import CoreAudio
import Observation

/// Row hover for the panel. The toolchain has no `@State` macro, so this transient bit of
/// view state lives in one shared observable instead.
/// ponytail: one panel is on screen at a time; move it into the view if that ever changes.
@Observable
final class PanelHover {
    static let shared = PanelHover()
    /// Section-qualified: a duplex device has the same id in both the output and input list.
    var row: String?

    static func key(_ d: AudioDevice, input: Bool) -> String { "\(input ? "in" : "out"):\(d.id)" }
}

struct MenuView: View {
    @Bindable var controller: Controller
    @Bindable var loginItem: LoginItem
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    private let hover = PanelHover.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("Output") {
                card {
                    ForEach(controller.outputs) { d in
                        deviceRow(d, input: false, selected: d.id == controller.defaultOutputID) {
                            controller.selectOutput(d.id)
                        }
                    }
                }
                volume
            }

            section("Input") {
                card {
                    ForEach(controller.inputs) { d in
                        deviceRow(d, input: true, selected: d.id == controller.defaultInputID) {
                            controller.selectInput(d.id)
                        }
                    }
                }
                switchRow("Lock input", isOn: $controller.inputLocked)
            }

            Divider()
            calls

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Button("Setup guide…") {
                    openWindow(id: "setup")
                    NSApp.activate(ignoringOtherApps: true)
                    dismiss()
                }
                .buttonStyle(.borderless)
                switchRow("Launch at login", isOn: $loginItem.enabled)
                if !loginItem.error.isEmpty {
                    note(loginItem.error, color: .orange)
                }
            }

            Divider()
            footerButton("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 340)
        .onAppear { controller.reconcile() }
    }

    // MARK: sections

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Card radius 10 with 4pt of padding, so the 6pt row highlight stays concentric with it.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func deviceRow(_ d: AudioDevice, input: Bool, selected: Bool, action: @escaping () -> Void) -> some View {
        let key = PanelHover.key(d, input: input)
        return Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol(d, input: input))
                    .font(.system(size: 16))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(d.name)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(hover.row == key ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .onHover { inside in
            if inside { hover.row = key } else if hover.row == key { hover.row = nil }
        }
    }

    /// Transport decides the glyph: built-in, Bluetooth headset, or anything else.
    private func symbol(_ d: AudioDevice, input: Bool) -> String {
        if input { return d.transport == kAudioDeviceTransportTypeBuiltIn ? "mic.fill" : "mic" }
        switch d.transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return "hifispeaker.fill"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return d.name.localizedCaseInsensitiveContains("AirPods Pro") ? "airpodspro" : "headphones"
        default:
            return "speaker.wave.2.fill"
        }
    }

    @ViewBuilder
    private var volume: some View {
        if let level = controller.outputVolume {
            Slider(value: Binding(get: { level }, set: { controller.setOutputVolume($0) }), in: 0...1) {
                EmptyView()
            } minimumValueLabel: {
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityLabel("Output volume")
            .padding(.horizontal, 2)
        } else {
            note("No volume control on this output")
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.body)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .frame(height: 22)
    }

    private var calls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let problem = controller.driverStatus {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    Text(problem)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(controller.callsInUse ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CallLane")
                            .font(.body)
                        Text("→ \(controller.defaultOutputDevice?.name ?? "no output")")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(controller.callsInUse ? "in use" : "idle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            if !controller.status.isEmpty {
                note(controller.status, color: .orange)
            }
            note("Pick “CallLane” as the speaker in each call app.")
        }
    }

    private func note(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color ?? Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Small secondary text on every macOS version. The glass button style was tried on
    /// macOS 26 and rendered as filled pills, which reads as prominent; quit actions must not.
    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
