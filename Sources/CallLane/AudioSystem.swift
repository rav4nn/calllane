import AVFoundation
import CoreAudio
import Foundation
import os

let log = Logger(subsystem: "dev.rav4nn.calllane", category: "audio")

struct AudioDevice: Equatable, Identifiable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32
    let hasInput: Bool
    let hasOutput: Bool
    var isAggregate: Bool { transport == kAudioDeviceTransportTypeAggregate }
}

enum AudioScope {
    case input, output
    var raw: AudioObjectPropertyScope {
        self == .input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput
    }
}

struct AudioError: Error, CustomStringConvertible {
    let what: String
    let status: OSStatus
    var description: String { "\(what) failed (\(status))" }
}

final class ListenerToken {
    fileprivate let object: AudioObjectID
    fileprivate var address: AudioObjectPropertyAddress
    fileprivate let block: AudioObjectPropertyListenerBlock
    fileprivate init(object: AudioObjectID, address: AudioObjectPropertyAddress, block: @escaping AudioObjectPropertyListenerBlock) {
        self.object = object; self.address = address; self.block = block
    }
    deinit { if object != 0 { AudioObjectRemovePropertyListenerBlock(object, &address, .main, block) } }
}

extension ListenerToken {
    static func fake() -> ListenerToken {
        ListenerToken(object: 0, address: AudioObjectPropertyAddress(), block: { _, _ in })
    }
}

protocol AudioSystem {
    func devices() -> [AudioDevice]
    func defaultOutput() -> AudioObjectID?
    func defaultInput() -> AudioObjectID?
    func setDefaultOutput(_ id: AudioObjectID) throws
    func setDefaultInput(_ id: AudioObjectID) throws
    func volume(_ id: AudioObjectID, scope: AudioScope) -> Float?
    func setVolume(_ id: AudioObjectID, scope: AudioScope, _ value: Float) throws
    func isRunningSomewhere(_ id: AudioObjectID) -> Bool
    /// Resolves a device UID; nil when no device has it. Finds hidden devices too.
    func deviceID(forUID uid: String) -> AudioObjectID?
    /// `CFBundleShortVersionString` of the installed CallLane driver; nil when not installed.
    func driverVersion() -> String?
    /// Microphone permission covers every input device, the hidden tap included. Without it
    /// macOS feeds an app zeros and reports no error. nil: the user was not asked yet.
    func microphoneAllowed() -> Bool?
    /// Shows the system prompt once; `completion` runs on the main queue after the answer.
    func requestMicrophone(_ completion: @escaping () -> Void)
    func destroyAggregate(_ id: AudioObjectID) throws
    /// Returns nil when CoreAudio refuses the registration.
    func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ handler: @escaping () -> Void) -> ListenerToken?
}

final class CoreAudioSystem: AudioSystem {
    static let driverPlist = "/Library/Audio/Plug-Ins/HAL/CallLane.driver/Contents/Info.plist"

    private let system = AudioObjectID(kAudioObjectSystemObject)
    private let driverPlist: String

    init(driverPlist: String = CoreAudioSystem.driverPlist) {
        self.driverPlist = driverPlist
    }

    private func address(_ selector: AudioObjectPropertySelector,
                         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func get<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var a = addr
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func set<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T, what: String) throws {
        var a = addr
        var v = value
        let status = withUnsafePointer(to: &v) {
            AudioObjectSetPropertyData(object, &a, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
        if status != noErr { throw AudioError(what: what, status: status) }
    }

    private func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var a = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value)
        guard status == noErr, let cf = value?.takeRetainedValue() else { return "" }
        return cf as String
    }

    private func hasStreams(_ id: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        var a = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr && size > 0
    }

    func devices() -> [AudioDevice] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { id in
            AudioDevice(id: id,
                        uid: string(id, kAudioDevicePropertyDeviceUID),
                        name: string(id, kAudioObjectPropertyName),
                        transport: get(id, address(kAudioDevicePropertyTransportType), UInt32(0)) ?? 0,
                        hasInput: hasStreams(id, kAudioObjectPropertyScopeInput),
                        hasOutput: hasStreams(id, kAudioObjectPropertyScopeOutput))
        }
    }

    func defaultOutput() -> AudioObjectID? {
        let id = get(system, address(kAudioHardwarePropertyDefaultOutputDevice), AudioObjectID(0)) ?? 0
        return id == 0 ? nil : id
    }

    func defaultInput() -> AudioObjectID? {
        let id = get(system, address(kAudioHardwarePropertyDefaultInputDevice), AudioObjectID(0)) ?? 0
        return id == 0 ? nil : id
    }

    func setDefaultOutput(_ id: AudioObjectID) throws {
        try set(system, address(kAudioHardwarePropertyDefaultOutputDevice), id, what: "set default output")
    }

    func setDefaultInput(_ id: AudioObjectID) throws {
        try set(system, address(kAudioHardwarePropertyDefaultInputDevice), id, what: "set default input")
    }

    // Main element first, then channels 1 and 2. Aggregates have neither and return nil.
    private func volumeElements(_ id: AudioObjectID, _ scope: AudioScope) -> [AudioObjectPropertyElement] {
        [kAudioObjectPropertyElementMain, 1, 2].filter { el in
            var a = address(kAudioDevicePropertyVolumeScalar, scope.raw, el)
            return AudioObjectHasProperty(id, &a)
        }
    }

    func volume(_ id: AudioObjectID, scope: AudioScope) -> Float? {
        guard let el = volumeElements(id, scope).first else { return nil }
        return get(id, address(kAudioDevicePropertyVolumeScalar, scope.raw, el), Float(0))
    }

    func setVolume(_ id: AudioObjectID, scope: AudioScope, _ value: Float) throws {
        let els = volumeElements(id, scope)
        if els.isEmpty { throw AudioError(what: "set volume", status: kAudioHardwareUnknownPropertyError) }
        let targets = els.contains(kAudioObjectPropertyElementMain) ? [kAudioObjectPropertyElementMain] : els
        for el in targets {
            try set(id, address(kAudioDevicePropertyVolumeScalar, scope.raw, el), max(0, min(1, value)), what: "set volume")
        }
    }

    func isRunningSomewhere(_ id: AudioObjectID) -> Bool {
        (get(id, address(kAudioDevicePropertyDeviceIsRunningSomewhere), UInt32(0)) ?? 0) != 0
    }

    func deviceID(forUID uid: String) -> AudioObjectID? {
        var a = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cf = uid as CFString
        var id: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &cf) {
            AudioObjectGetPropertyData(system, &a, UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        // An unknown UID answers noErr with kAudioObjectUnknown (0).
        return status == noErr && id != 0 ? id : nil
    }

    func driverVersion() -> String? {
        NSDictionary(contentsOfFile: driverPlist)?["CFBundleShortVersionString"] as? String
    }

    func microphoneAllowed() -> Bool? {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return nil
        default: return false
        }
    }

    func requestMicrophone(_ completion: @escaping () -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async(execute: completion) }
    }

    /// Not part of `AudioSystem` any more: the app stopped creating aggregates in v0.2.
    /// The live test still creates one to exercise `deviceID(forUID:)` and `destroyAggregate`.
    func createAggregate(name: String, uid: String, subDeviceUID: String) throws -> AudioObjectID {
        let desc: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: 0,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceMainSubDeviceKey: subDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: subDeviceUID]],
        ]
        var id: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(desc as CFDictionary, &id)
        if status != noErr { throw AudioError(what: "create aggregate", status: status) }
        return id
    }

    func destroyAggregate(_ id: AudioObjectID) throws {
        let status = AudioHardwareDestroyAggregateDevice(id)
        if status != noErr { throw AudioError(what: "destroy aggregate", status: status) }
    }

    func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ handler: @escaping () -> Void) -> ListenerToken? {
        let addr = address(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        var a = addr
        let status = AudioObjectAddPropertyListenerBlock(object, &a, .main, block)
        guard status == noErr else {
            log.error("listener \(selector) on \(object) failed: \(status)")
            return nil
        }
        return ListenerToken(object: object, address: addr, block: block)
    }
}
