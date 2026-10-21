import AppKit
import CoreAudio
import HanSearchCore

/// Observes application lifetime and reads CoreAudio IO flags, never audio buffers,
/// taps, project contents, accessibility or microphone/capture permissions.
final class OCRWorkActivityMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var value = OCRWorkActivity()
    private var generation = UUID()
    private let queue = DispatchQueue(label: "local.hansearch.work-protection", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    var changed: (@Sendable () -> Void)?
    private static let protectedApps = ["com.apple.logic10": "Logic Pro", "com.apple.FinalCut": "Final Cut Pro", "com.apple.FinalCutApp": "Final Cut Pro"]
    var snapshot: OCRWorkActivity { lock.lock(); defer { lock.unlock() }; return value }
    @MainActor func setEnabled(_ enabled: Bool) { if enabled { start() } else { stop() } }
    @MainActor private func start() {
        guard timer == nil else { return }
        lock.lock(); generation = UUID(); let token = generation; value.audio = .unavailable; lock.unlock()
        updateApps()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateApps() }
            })
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.updateAudio(generation: token)
            Task { @MainActor [weak self] in if self?.timer != nil { self?.updateApps() } }
        }; timer.resume(); self.timer = timer
        changed?()
    }
    @MainActor private func updateApps() {
        let names = Self.protectedAppNames(bundleIdentifiers: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        update { $0.protectedApp = names }
    }
    static func protectedAppNames(bundleIdentifiers: [String]) -> String? {
        Set(bundleIdentifiers.compactMap { protectedApps[$0] }).sorted().joined(separator: "、").nilIfEmpty
    }
    private func updateAudio(generation token: UUID) {
        let audio = Self.readAudioActivity()
        lock.lock()
        guard generation == token else { lock.unlock(); return }
        let didChange = value.audio != audio; value.audio = audio; lock.unlock()
        if didChange { changed?() }
    }
    @MainActor private func stop() {
        guard timer != nil else { return }
        timer?.cancel(); timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; observers = []
        lock.lock(); generation = UUID(); value = OCRWorkActivity(); lock.unlock()
    }
    private func update(_ mutate: (inout OCRWorkActivity) -> Void) {
        lock.lock(); let old = value; mutate(&value); let didChange = old != value; lock.unlock()
        if didChange { changed?() }
    }
    deinit {
        timer?.cancel()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    /// CoreAudio process IO flags are public on macOS 14.2+. Polling also covers
    /// drivers/OS versions which do not reliably deliver IO-state notifications.
    static func readAudioActivity() -> OCRWorkActivity.Audio {
        if #available(macOS 14.2, *) {
            guard let processes = objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) else { return .unavailable }
            var input = false, output = false, failed = false
            for process in processes {
                let i = flag(process, kAudioProcessPropertyIsRunningInput)
                let o = flag(process, kAudioProcessPropertyIsRunningOutput)
                input = input || i == true; output = output || o == true
                failed = failed || i == nil || o == nil
            }
            if input && output { return .inputAndOutput }
            if input { return .input }; if output { return .output }
            return failed ? .unavailable : .quiet
        }
        // Older OS versions cannot reliably distinguish direction. Conservatively
        // treat a running device as audio activity; never label it as recording.
        guard let devices = objectList(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices) else { return .unavailable }
        var failed = false
        for device in devices {
            guard let running = flag(device, kAudioDevicePropertyDeviceIsRunningSomewhere) else { failed = true; continue }
            if running { return .output }
        }
        return failed ? .unavailable : .quiet
    }
    private static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID]? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size % UInt32(MemoryLayout<AudioObjectID>.size) == 0, size <= 65_536 else { return nil }
        if size == 0 { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let result = values.withUnsafeMutableBytes { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0.baseAddress!) }
        guard result == noErr else { return nil }
        return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
