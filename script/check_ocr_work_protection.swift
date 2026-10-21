import Foundation
import HanSearchCore

final class WorkActivityFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var value = OCRWorkActivity(protectedApp: "Logic Pro")
    func read() -> OCRWorkActivity { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ newValue: OCRWorkActivity) { lock.lock(); value = newValue; lock.unlock() }
}
@main struct WorkProtectionChecks {
    @MainActor static func main() async throws {
        precondition(OCRWorkActivityMonitor.protectedAppNames(bundleIdentifiers: ["com.apple.logic10"]) == "Logic Pro")
        precondition(OCRWorkActivityMonitor.protectedAppNames(bundleIdentifiers: ["com.apple.FinalCut"]) == "Final Cut Pro")
        precondition(OCRWorkActivityMonitor.protectedAppNames(bundleIdentifiers: ["com.apple.FinalCutApp"]) == "Final Cut Pro")
        precondition(OCRWorkActivityMonitor.protectedAppNames(bundleIdentifiers: ["com.apple.logic10", "com.apple.logic10"]) == "Logic Pro")
        precondition(OCRWorkActivityMonitor.protectedAppNames(bundleIdentifiers: ["com.example.logic10", "com.example.normal"]) == nil)
        let fixture = WorkActivityFixture()
        let policy = OCRResourcePolicy(allowBattery: false, idleOnly: false,
            state: { OCRResourceState(power: .external, idleSeconds: 900) }, activity: { fixture.read() })
        precondition(policy.decision() == .protectedApp)
        fixture.set(OCRWorkActivity(audio: .input)); precondition(policy.decision() == .audioInput)
        fixture.set(OCRWorkActivity(audio: .output)); precondition(policy.decision() == .audioOutput)
        policy.configure(allowBattery: false, idleOnly: false, protectWork: true, protectAudio: false)
        precondition(policy.decision() == .idle)
        fixture.set(OCRWorkActivity(protectedApp: "Logic Pro")); precondition(policy.decision() == .protectedApp)
        policy.configure(allowBattery: false, idleOnly: false, protectWork: false, protectAudio: true)
        precondition(policy.decision() == .idle)
        let suite = "HanWorkProtection." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: base) }
        let store = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults, sourcePreferences: defaults,
            documentIndexURL: base.appendingPathComponent("Index/Documents.sqlite"),
            ocrResourceState: { OCRResourceState(power: .external, idleSeconds: 900) }, ocrWorkActivity: { fixture.read() })
        precondition(store.ocrProtectWork && store.ocrProtectAudio)
        store.reviewOCRResources(); precondition(store.ocrWorkDecision == .protectedApp)
        store.ocrProtectWork = false; precondition(store.ocrWorkDecision == .idle)
        store.ocrProtectWork = true; fixture.set(OCRWorkActivity(audio: .input)); store.reviewOCRResources()
        precondition(store.ocrWorkDecision == .audioInput && store.ocrWorkActivity.audio == .input)
        store.indexSnapshot.deferredOCR = 1; store.indexPaused = true
        fixture.set(OCRWorkActivity()); store.reviewOCRResources()
        precondition(!store.indexing && store.indexPaused, "Work recovery must not override manual pause")
        store.ocrProtectAudio = false
        let restored = SearchStore(loadSources: false, fileAccess: FileAccessBookmarks(defaults: defaults), taskPreferences: defaults, sourcePreferences: defaults,
            documentIndexURL: base.appendingPathComponent("Index/Documents.sqlite"), ocrWorkActivity: { OCRWorkActivity() })
        precondition(restored.ocrProtectWork && !restored.ocrProtectAudio)
        // Read flags only, with no device opened, audio captured or permissions requested.
        let live = OCRWorkActivityMonitor.readAudioActivity()
        let monitor = OCRWorkActivityMonitor()
        monitor.setEnabled(true); try await Task.sleep(for: .milliseconds(300))
        monitor.setEnabled(false); precondition(monitor.snapshot == OCRWorkActivity())
        print("CoreAudio metadata probe completed: \(live)")
        print("PASS: exact work-app IDs, conservative app-open protection, input/output/unknown activity decisions, opt-outs, local preference persistence and manual-pause precedence; fake state plus read-only CoreAudio flags")
    }
}
