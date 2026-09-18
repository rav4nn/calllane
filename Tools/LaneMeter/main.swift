// LaneMeter: a floating on-screen meter for demo recordings.
// Rows: music level (Spotify), call level (loudest running call app), headphones sample rate.
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
func defaultOutput() -> AudioObjectID { get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(0)) }
func processObject(pid: pid_t) -> AudioObjectID {
    var a = addr(kAudioHardwarePropertyTranslatePIDToProcessObject); var p = pid; var out = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<pid_t>.size), &p, &size, &out)
    return out
}

/// The IOProc writes here; the model reads here. Owned by both, so a tap can die mid-callback.
/// ponytail: a plain Float; aligned 4-byte stores are atomic on arm64, and a torn meter frame is harmless.
final class Level { var rms: Float = 0 }

/// One process tap feeding an RMS reading. Destroyed on deinit, which Swift also runs when
/// the initializer throws after the stored properties are set, so a failed init leaks nothing.
final class Tap {
    let level = Level()
    var rms: Float { level.rms }
    private var tap = AudioObjectID(0), agg = AudioObjectID(0), proc: AudioDeviceIOProcID?
    let pid: pid_t

    init(pid: pid_t, name: String) throws {
        self.pid = pid
        let desc = CATapDescription(stereoMixdownOfProcesses: [processObject(pid: pid)])
        desc.uuid = UUID(); desc.muteBehavior = .unmuted; desc.name = "LaneMeter \(name)"; desc.isPrivate = true
        var err = AudioHardwareCreateProcessTap(desc, &tap)
        guard err == noErr else { throw NSError(domain: "tap", code: Int(err)) }
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LaneMeter \(name)",
            kAudioAggregateDeviceUIDKey: "lanemeter-\(desc.uuid.uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: str(defaultOutput(), kAudioDevicePropertyDeviceUID)]],
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

let musicApps = ["com.spotify.client": "Spotify", "com.apple.Music": "Music", "com.apple.Safari": "Safari", "tv.plex.desktop": "Plex"]
let callApps = ["com.google.Chrome": "Meet", "net.whatsapp.WhatsApp": "WhatsApp", "com.apple.FaceTime": "FaceTime",
                "us.zoom.xos": "Zoom", "com.tinyspeck.slackmacgap": "Slack", "com.microsoft.teams2": "Teams", "com.hnc.Discord": "Discord"]

let allApps = musicApps.merging(callApps, uniquingKeysWith: { $1 })

final class Model: ObservableObject {
    @Published var music: Float = -60
    @Published var musicName = "Music"
    @Published var call: Float = -60
    @Published var callName = "Call"
    @Published var device = ""
    @Published var rate = 0.0
    @Published var error = ""
    private var taps: [String: Tap] = [:]   // bundle id → tap
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
        let (m, mn) = loudest(musicApps); music = smooth(music, m); musicName = mn ?? "Music"
        let (c, cn) = loudest(callApps); call = smooth(call, c); callName = cn ?? "Call"
    }
    private func smooth(_ old: Float, _ new: Float) -> Float { new > old ? new : old * 0.85 + new * 0.15 }
    private func loudest(_ apps: [String: String]) -> (Float, String?) {
        var best: Float = -60; var name: String?
        for (bundle, label) in apps {
            guard let t = taps[bundle] else { continue }
            let db = max(-60, 20 * log10(max(t.rms, 1e-5)))
            if db > best || name == nil { best = db; name = label }
        }
        return (best, name)
    }
    /// Tap every running music or call app; drop taps whose app quit. Runs once a second.
    private func refreshTaps() {
        let running = Dictionary(NSWorkspace.shared.runningApplications
            .compactMap { app in app.bundleIdentifier.map { ($0, app.processIdentifier) } }, uniquingKeysWith: { first, _ in first })
        for (bundle, tap) in taps where running[bundle] != tap.pid { taps[bundle] = nil }
        for (bundle, label) in allApps {
            guard taps[bundle] == nil, let pid = running[bundle] else { continue }
            do { taps[bundle] = try Tap(pid: pid, name: label) } catch { self.error = "\(label): \(error.localizedDescription)" }
        }
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
            Text(String(format: "%3.0f dB", db)).font(.system(size: 22, weight: .medium, design: .monospaced)).frame(width: 90, alignment: .trailing)
        }
    }
}

struct MeterView: View {
    @ObservedObject var model: Model
    var quality: (String, Color) {
        switch model.rate {
        case 44100...: return ("Listening, \(Int(model.rate / 1000)) kHz", .green)
        case 1...: return ("Headset, \(Int(model.rate / 1000)) kHz", .orange)
        default: return ("No output device", .gray)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Bar(title: model.musicName, db: model.music, color: .yellow)
            Bar(title: model.callName, db: model.call, color: .green)
            HStack(spacing: 14) {
                Text("Headphones").font(.system(size: 22, weight: .semibold)).frame(width: 150, alignment: .leading)
                Text(quality.0).font(.system(size: 22, weight: .medium)).foregroundStyle(quality.1)
                Spacer()
                Text(model.device).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            }
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
