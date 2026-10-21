import Foundation
import AppKit
import CoreText
import HanSearchCore

final class OCRPowerFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var value = OCRResourceState(power: .battery, batteryPercent: 90, idleSeconds: 300)
    func read() -> OCRResourceState { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ state: OCRResourceState) { lock.lock(); defer { lock.unlock() }; value = state }
}

@main struct OCRStoreChecks {
    @MainActor static func main() async throws {
        let suite = "HanOCRStore." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(false, forKey: "autoRefreshSources.v1")
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(suite), root = base.appendingPathComponent("Selected")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: base) }
        let bitmap = CGContext(data: nil, width: 1400, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 1400, height: 400))
        bitmap.textPosition = CGPoint(x: 80, y: 180)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "BACKGROUND OCR FIXTURE", attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, 60, nil)])), bitmap)
        var box = CGRect(x: 0, y: 0, width: 700, height: 200)
        let pdf = CGContext(root.appendingPathComponent("fixture.pdf") as CFURL, mediaBox: &box, nil)!
        for _ in 0..<9 { pdf.beginPDFPage(nil); pdf.draw(bitmap.makeImage()!, in: box); pdf.endPDFPage() }; pdf.closePDF()
        let access = FileAccessBookmarks(defaults: defaults)
        let power = OCRPowerFixture()
        let store = SearchStore(loadSources: false, fileAccess: access, taskPreferences: defaults, sourcePreferences: defaults,
            eventCalendarLoader: { [] }, contentSearcher: { _, _ in SearchResponse(items: []) }, documentIndexURL: base.appendingPathComponent("Index/Documents.sqlite"), ocrResourceState: { power.read() })
        precondition(store.ocrEnabled)
        try store.addDocumentRoots([root])
        for _ in 0..<1000 { if !store.indexing { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(!store.ocrAllowBattery && !store.ocrIdleOnly)
        precondition(!store.indexing && store.indexSnapshot.deferredOCR == 1 && store.indexSnapshot.ocrPages == 0)
        precondition(store.sourceHealth[.contents]?.phase == .waiting)
        let attempted = store.sourceHealth[.contents]?.lastAttempt
        store.reviewOCRResources()
        precondition(!store.indexing && store.sourceHealth[.contents]?.lastAttempt == attempted, "No repeated rescans while waiting")
        store.pauseDocumentIndex()
        power.set(OCRResourceState(power: .external, idleSeconds: 300))
        store.reviewOCRResources(); precondition(!store.indexing, "Manual pause must survive power recovery")
        store.indexPaused = false
        store.reviewOCRResources()
        precondition(store.indexing, "Power recovery automatically resumes without new consent")
        var observedPages = false, observedPending = false
        // Background priority may be deliberately delayed under system load.
        for _ in 0..<9000 {
            observedPages = observedPages || store.indexCurrentPage > 0
            observedPending = observedPending || store.indexSnapshot.pendingOCR > 0
            if !store.indexing && store.indexSnapshot.files == 1 && store.indexSnapshot.pendingOCR == 0 && store.indexSnapshot.deferredOCR == 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(observedPages && observedPending && store.indexSnapshot.ocrPages == 9 && !store.indexing, "Store OCR: pages=\(store.indexSnapshot.ocrPages), pending=\(store.indexSnapshot.pendingOCR), deferred=\(store.indexSnapshot.deferredOCR), indexing=\(store.indexing), observedPages=\(observedPages), observedPending=\(observedPending), issues=\(store.indexSnapshot.issues.map { $0.reason.rawValue })")
        store.mode = .contents; store.query = "BACKGROUND"; store.search()
        for _ in 0..<500 { if !store.searching && !store.results.isEmpty { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(store.results.first?.isOCR == true && store.results.first?.matchPages.first == 1)
        store.ocrIdleOnly = true; store.ocrAllowBattery = true
        precondition(defaults.bool(forKey: "documentOCRIdleOnly.v1") && defaults.bool(forKey: "documentOCRBattery.v1"))
        store.ocrEnabled = false; store.rebuildIndex()
        for _ in 0..<1000 { if !store.indexing { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(defaults.object(forKey: "documentOCR.v1") as? Bool == false && store.indexSnapshot.ocrPages == 0)
        let restored = SearchStore(loadSources: false, fileAccess: access, taskPreferences: defaults, sourcePreferences: defaults, documentIndexURL: base.appendingPathComponent("Index/Documents.sqlite"))
        precondition(!restored.ocrEnabled && restored.ocrIdleOnly && restored.ocrAllowBattery)
        store.pauseDocumentIndex(); store.clearDocumentScopes()
        for _ in 0..<500 { if !store.indexing { break }; try await Task.sleep(for: .milliseconds(10)) }
        precondition(store.documentRoots.isEmpty && !FileManager.default.fileExists(atPath: store.documentIndexURL.path))
        access.clear()
        print("PASS: battery deferral, no waiting rescans, pause preservation, automatic power recovery, energy preferences; real store on-device OCR, visible page progress, automatic continuation with source refresh disabled, search location metadata, persisted OCR preference and scoped index removal; synthetic PDF and isolated preferences only")
    }
}
