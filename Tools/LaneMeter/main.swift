// LaneMeter: a floating on-screen meter for demo recordings.
// Rows: media level (everything but call apps), call level (call apps and their helpers), headphones sample rate.
// Levels come from CoreAudio process taps (macOS 14.2+). The window stays above every app.
import AppKit
import CoreAudio
import SwiftUI

// MARK: CoreAudio helpers

func addr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}
func get<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ v: T) -> T {
    var a = addr(sel); var v = v; var size = UInt32(MemoryLayout<T>.size)
    AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v); return v
}
func str(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
    var a = addr(sel); var s: CFString = "" as CFString; var size = UInt32(MemoryLayout<CFString>.size)
    AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &s); return s as String
}
func defaultInput() -> AudioObjectID { get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, AudioObjectID(0)) }
func defaultOutput() -> AudioObjectID { get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(0)) }

/// The IOProc writes here; the model reads here. Owned by both, so a tap can die mid-callback.
/// ponytail: a plain Float; aligned 4-byte stores are atomic on arm64, and a torn meter frame is harmless.
final class Level { var rms: Float = 0 }

/// One process tap feeding an RMS reading. Destroyed on deinit, which Swift also runs when
/// the initializer throws after the stored properties are set, so a failed init leaks nothing.
final class Tap {
    let level = Level()
    var rms: Float { level.rms }
    private var tap = AudioObjectID(0), agg = AudioObjectID(0), proc: AudioDeviceIOProcID?

    init(_ desc: CATapDescription, name: String) throws {
        desc.uuid = UUID(); desc.muteBehavior = .unmuted; desc.name = "LaneMeter \(name)"; desc.isPrivate = true
        var err = AudioHardwareCreateProcessTap(desc, &tap)
        guard err == noErr else { throw NSError(domain: "tap", code: Int(err)) }
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LaneMeter \(name)",
            kAudioAggregateDeviceUIDKey: "lanemeter-\(desc.uuid.uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        err = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &agg)
        guard err == noErr else { throw NSError(domain: "aggregate", code: Int(err)) }
        // Process taps deliver Float32 PCM; the aggregate inherits that format.
        let level = self.level
        err = AudioDeviceCreateIOProcIDWithBlock(&proc, agg, nil) { _, inData, _, _, _ in
            var sum: Float = 0; var n = 0
            for b in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData)) {
                guard let data = b.mData, b.mDataByteSize >= 4 else { continue }
                let p = data.assumingMemoryBound(to: Float.self); let c = Int(b.mDataByteSize) / 4
                for i in 0..<c { sum += p[i] * p[i] }; n += c
            }
            if n > 0 { level.rms = (sum / Float(n)).squareRoot() }
        }
        guard err == noErr else { throw NSError(domain: "ioproc", code: Int(err)) }
        err = AudioDeviceStart(agg, proc)
        guard err == noErr else { throw NSError(domain: "start", code: Int(err)) }
    }
    deinit {
        if let proc { AudioDeviceStop(agg, proc); AudioDeviceDestroyIOProcID(agg, proc) }
        if agg != 0 { AudioHardwareDestroyAggregateDevice(agg) }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
    }
}

// MARK: Model

/// Bundle id prefixes of call apps. Every CoreAudio process whose bundle id starts with one of
/// these counts as "call" (helpers included); everything else that makes sound is "media".
let callPrefixes = ["com.google.Chrome", "net.whatsapp.WhatsApp", "com.apple.FaceTime", "com.apple.avconferenced",
                    "us.zoom", "com.tinyspeck.slackmacgap", "com.microsoft.teams", "com.hnc.Discord"]

/// "com.google.Chrome.helper" → "Chrome"; "com.apple.avconferenced" → "FaceTime".
func shortName(_ bundle: String) -> String {
    if bundle.hasPrefix("com.apple.avconferenced") || bundle.hasPrefix("com.apple.FaceTime") { return "FaceTime" }
    let parts = bundle.replacingOccurrences(of: ".helper", with: "").split(separator: ".")
    return parts.count >= 3 ? String(parts[2]) : bundle
}

/// All CoreAudio process objects with their bundle ids, or nil when the HAL refuses the list.
func processObjects() -> [(AudioObjectID, String)]? {
    var a = addr(kAudioHardwarePropertyProcessObjectList); var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return nil }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return nil }
    return ids.map { ($0, str($0, kAudioProcessPropertyBundleID)) }
}

final class Model: ObservableObject {
    @Published var media: Float = -60
    @Published var call: Float = -60
    @Published var device = ""
    @Published var rate = 0.0
    @Published var mic = ""
    @Published var micUsers = ""
    @Published var error = ""
    private var mediaTap: Tap?, callTap: Tap?
    private var callObjects: Set<AudioObjectID> = []
    private var tick = 0

    init() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [unowned self] _ in self.poll() }
    }

    private func poll() {
        tick += 1
        if tick % 20 == 1 { refreshTaps() }
        let out = defaultOutput()
        device = str(out, kAudioObjectPropertyName)
        rate = get(out, kAudioDevicePropertyNominalSampleRate, Double(0))
        mic = str(defaultInput(), kAudioObjectPropertyName)
        media = smooth(media, db(mediaTap)); call = smooth(call, db(callTap))
    }
    private func db(_ tap: Tap?) -> Float { max(-60, 20 * log10(max(tap?.rms ?? 0, 1e-5))) }
    private func smooth(_ old: Float, _ new: Float) -> Float { new > old ? new : old * 0.85 + new * 0.15 }

    /// Rebuild both taps when the set of call processes changes. Runs once a second.
    /// Both taps are built first and the state commits together, so a failure keeps the last good pair.
    private func refreshTaps() {
        guard let procs = processObjects() else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        // Who holds a microphone open right now. Any of these on the AirPods' mic forces the headset profile.
        micUsers = Set(procs.filter { get($0.0, kAudioProcessPropertyIsRunningInput, UInt32(0)) != 0 }
            .map { shortName($0.1) }).sorted().joined(separator: ", ")
        let calls = Set(procs.filter { obj, bundle in
            callPrefixes.contains { bundle.hasPrefix($0) } && get(obj, kAudioProcessPropertyPID, pid_t(0)) != me
        }.map { $0.0 })
        guard calls != callObjects || mediaTap == nil else { return }
        let objs = Array(calls)
        do {
            let media = try Tap(CATapDescription(stereoGlobalTapButExcludeProcesses: objs), name: "media")
            let call = objs.isEmpty ? nil : try Tap(CATapDescription(stereoMixdownOfProcesses: objs), name: "call")
            (mediaTap, callTap, callObjects, error) = (media, call, calls, "")
        } catch { self.error = "tap: \(error.localizedDescription)" }
    }
}

// MARK: View

struct Bar: View {
    let title: String, db: Float, color: Color
    var body: some View {
        HStack(spacing: 14) {
            Text(title).font(.system(size: 22, weight: .semibold)).frame(width: 150, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(color).frame(width: max(0, g.size.width * CGFloat((db + 60) / 60)))
                }
            }.frame(height: 18)
            Text(String(format: "%3.0f%%", max(0, (db + 60) / 60 * 100))).font(.system(size: 22, weight: .medium, design: .monospaced)).frame(width: 80, alignment: .trailing)
        }
    }
}

struct MeterView: View {
    @ObservedObject var model: Model
    var quality: (String, Color) {
        switch model.rate {
        case 44100...: return ("High quality (\(Int(model.rate / 1000)) kHz)", .green)
        case 1...: return ("Low quality (\(Int(model.rate / 1000)) kHz)", .orange)
        default: return ("No output device", .gray)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Bar(title: "Media", db: model.media, color: .yellow)
            Bar(title: "Call", db: model.call, color: .green)
            HStack(spacing: 14) {
                Text("Headphones").font(.system(size: 22, weight: .semibold)).frame(width: 150, alignment: .leading)
                Text(quality.0).font(.system(size: 22, weight: .medium)).foregroundStyle(quality.1)
            }
            HStack(spacing: 14) {
                Text("Mic").font(.system(size: 22, weight: .semibold)).frame(width: 150, alignment: .leading)
                Text(model.mic).font(.system(size: 22, weight: .medium)).foregroundStyle(model.mic == model.device ? .orange : .green)
                    .lineLimit(1)
            }
            Text(model.micUsers.isEmpty ? model.device : "\(model.device)  ·  mic open in \(model.micUsers)")
                .font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            if !model.error.isEmpty { Text(model.error).font(.system(size: 13)).foregroundStyle(.red) }
        }
        .padding(22)
        .frame(width: 560)
        .background(Color.black.opacity(0.88))
        .preferredColorScheme(.dark)
    }
}

// MARK: App

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let model = Model()
let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
panel.title = "LaneMeter"
panel.titlebarAppearsTransparent = true
panel.titleVisibility = .hidden
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.isMovableByWindowBackground = true
panel.contentView = NSHostingView(rootView: MeterView(model: model))
panel.setFrameAutosaveName("LaneMeter")
panel.setContentSize(panel.contentView!.fittingSize)
panel.center()
panel.orderFrontRegardless()
final class Delegate: NSObject, NSWindowDelegate { func windowWillClose(_ n: Notification) { app.terminate(nil) } }
let delegate = Delegate(); panel.delegate = delegate
app.run()
