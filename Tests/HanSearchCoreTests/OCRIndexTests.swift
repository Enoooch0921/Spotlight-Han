import Foundation
import AppKit
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import SQLite3
import HanSearchCore

private final class OCRPageAllowance: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining = 1
    func decision() -> OCRWorkDecision {
        lock.lock(); defer { lock.unlock() }
        if remaining == 0 { return .waitingForPower }
        remaining -= 1; return .idle
    }
}

extension ChineseSearchTests {
    func testOCRIndex() throws {
        func check(_ condition: @autoclosure () throws -> Bool, _ message: String = "OCR expectation failed") rethrows { let value = try condition(); precondition(value, message) }
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("HanOCR-" + UUID().uuidString)
        let root = base.appendingPathComponent("Selected"), outside = base.appendingPathComponent("Outside")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        func image(_ lines: [String]) -> CGImage {
            let context = CGContext(data: nil, width: 1800, height: 600, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1800, height: 600))
            for (index, text) in lines.enumerated() {
                let attributes: [NSAttributedString.Key: Any] = [.font: CTFontCreateWithName("PingFangTC-Regular" as CFString, 64, nil), .foregroundColor: CGColor(gray: 0, alpha: 1)]
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
                context.textPosition = CGPoint(x: 70, y: 450 - index * 110); CTLineDraw(line, context)
            }
            return context.makeImage()!
        }
        let original = image(["保固證明 教會活動", "设备型号 DL32", "WARRANTY TEST"])
        func png(_ image: CGImage, _ url: URL) {
            let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil); precondition(CGImageDestinationFinalize(dest))
        }
        let photo = root.appendingPathComponent("receipt.png"), pdfURL = root.appendingPathComponent("scan.pdf")
        png(original, photo); png(original, outside.appendingPathComponent("private.png"))
        func pdf(_ url: URL, count: Int, mixed: Bool = false) {
            var box = CGRect(x: 0, y: 0, width: 900, height: 300)
            let context = CGContext(url as CFURL, mediaBox: &box, nil)!
            for index in 0..<count {
                context.beginPDFPage(nil)
                if mixed && index == 0 {
                    context.textPosition = CGPoint(x: 30, y: 150)
                    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Selectable native first page", attributes: [.font: CTFontCreateWithName("Helvetica" as CFString, 32, nil)])), context)
                } else {
                    let bitmap = index == 8 ? image(["FINALMARKER PAGE NINE", "接續辨識測試"]) : original
                    context.draw(bitmap, in: box)
                }
                context.endPDFPage()
            }
            context.closePDF()
        }
        pdf(pdfURL, count: 2, mixed: true)
        precondition(PDFDocument(url: pdfURL)?.page(at: 1)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true, "Fixture scan must not already contain a text layer")
        let long = root.appendingPathComponent("long.pdf"); pdf(long, count: 9)
        let database = base.appendingPathComponent("Index/Documents.sqlite")
        let index = PersistentDocumentIndex(databaseURL: database)
        let first = try index.synchronize(roots: [root])
        precondition(first.pendingOCR == 1 && first.searchable == 3 && first.ocrPages >= 10, "First pass must commit a bounded OCR batch")
        func hits(_ query: String) throws -> [SearchItem] { try index.search(query: query, roots: [root], mode: .contents).items }
        let traditional = try hits("保固"), simplified = try hits("教会")
        precondition(traditional.contains { $0.url == photo && $0.isOCR && $0.excerpt.contains("保固") })
        precondition(simplified.contains { $0.url == pdfURL && $0.isOCR && $0.matchPages == [2] }, "Scanned PDF must report its actual matching page")
        try check(hits("DL32").contains { $0.url == photo && $0.isOCR })
        try check(hits("Selectable").contains { $0.url == pdfURL && !$0.isOCR && $0.matchPages == [1] })
        precondition(!traditional.contains { $0.url.path.hasPrefix(outside.path) })
        try check(hits("FINALMARKER").isEmpty, "Unprocessed pages must not invent hits")
        let cancellation = ProcessCancellation(); cancellation.cancel()
        do { _ = try index.synchronize(roots: [root], cancellation: cancellation); preconditionFailure("Expected cancellation") } catch is CancellationError { }
        try check(hits("保固").count == traditional.count, "Pause preserves committed chunks")
        let second = try index.synchronize(roots: [root])
        precondition(second.pendingOCR == 0 && second.unfinished == 0 && second.reused == 2)
        try check(hits("FINALMARKER").contains { $0.url == long && $0.matchPages == [9] && $0.isOCR })
        let resumed = try index.synchronize(roots: [root]); precondition(resumed.extracted == 0 && resumed.reused == 3)
        let disabled = PersistentDocumentIndex(databaseURL: database, ocrEnabled: false)
        _ = try disabled.synchronize(roots: [root])
        try check(hits("保固").isEmpty, "Disabling OCR must not leave old OCR text searchable")
        try check(hits("Selectable").count == 1)
        _ = try index.synchronize(roots: [root]); _ = try index.synchronize(roots: [root])
        png(image(["REPLACEMENTMARKER", "新內容"]), photo)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: photo.path)
        _ = try index.synchronize(roots: [root])
        try check(hits("REPLACEMENTMARKER").contains { $0.url == photo })
        try check(hits("保固").allSatisfy { $0.url != photo }, "Replacement removes old OCR grams and page text")
        try fm.removeItem(at: pdfURL)
        _ = try index.synchronize(roots: [root]); try check(hits("Selectable").isEmpty)
        precondition(CloudFileAvailability.needsDownload(isUbiquitous: true, status: .notDownloaded))
        precondition(CloudFileAvailability.needsDownload(isUbiquitous: true, status: nil))
        precondition(!CloudFileAvailability.needsDownload(isUbiquitous: true, status: .downloaded))
        precondition(!CloudFileAvailability.needsDownload(isUbiquitous: true, status: .current))
        precondition(!CloudFileAvailability.needsDownload(isUbiquitous: false, status: nil))
        precondition(CommonSearchFolder.allCases.count == 6 && Set(CommonSearchFolder.allCases.map(\.rawValue)).count == 6)
        try check(index.search(query: "保固", roots: [outside]).items.isEmpty)
        // Simulate a real version-1 database without discarding its existing FTS rows.
        let legacyRoot = base.appendingPathComponent("Legacy")
        try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try "LEGACYMARKER".write(to: legacyRoot.appendingPathComponent("legacy.txt"), atomically: true, encoding: .utf8)
        let deferredRoot = base.appendingPathComponent("Deferred")
        try fm.createDirectory(at: deferredRoot, withIntermediateDirectories: true)
        pdf(deferredRoot.appendingPathComponent("deferred.pdf"), count: 2, mixed: true)
        png(original, deferredRoot.appendingPathComponent("deferred.png"))
        let deferredDatabase = base.appendingPathComponent("DeferredIndex/Documents.sqlite")
        let waiting = PersistentDocumentIndex(databaseURL: deferredDatabase, ocrScheduler: OCRWorkScheduler { .waitingForPower })
        let held = try waiting.synchronize(roots: [deferredRoot])
        precondition(held.deferredOCR == 2 && held.pendingOCR == 0 && held.ocrPages == 0)
        try check(waiting.search(query: "Selectable", roots: [deferredRoot]).items.count == 1, "Native PDF text remains available while OCR waits")
        let energyResumed = PersistentDocumentIndex(databaseURL: deferredDatabase, ocrScheduler: OCRWorkScheduler { .idle })
        let resumedSnapshot = try energyResumed.synchronize(roots: [deferredRoot])
        precondition(resumedSnapshot.deferredOCR == 0 && resumedSnapshot.ocrPages == 2)
        try check(energyResumed.search(query: "保固", roots: [deferredRoot]).items.count == 2)
        let interruptedRoot = base.appendingPathComponent("PowerDrop")
        try fm.createDirectory(at: interruptedRoot, withIntermediateDirectories: true)
        try fm.copyItem(at: long, to: interruptedRoot.appendingPathComponent("drop.pdf"))
        let allowance = OCRPageAllowance(), interruptedDB = base.appendingPathComponent("DropIndex/Documents.sqlite")
        let dropping = PersistentDocumentIndex(databaseURL: interruptedDB, ocrScheduler: OCRWorkScheduler { allowance.decision() })
        let interrupted = try dropping.synchronize(roots: [interruptedRoot])
        precondition(interrupted.deferredOCR == 1 && interrupted.ocrPages == 1 && interrupted.searchable == 1)
        try check(dropping.search(query: "保固", roots: [interruptedRoot]).items.first?.matchPages == [1])
        try check(dropping.search(query: "FINALMARKER", roots: [interruptedRoot]).items.isEmpty)
        let recovered = PersistentDocumentIndex(databaseURL: interruptedDB, ocrScheduler: OCRWorkScheduler { .idle })
        let recovery = try recovered.synchronize(roots: [interruptedRoot])
        precondition(recovery.ocrPages == 9 && recovery.deferredOCR == 0 && recovery.pendingOCR == 0)
        try check(recovered.search(query: "FINALMARKER", roots: [interruptedRoot]).items.first?.matchPages == [9])
        let blankRoot = base.appendingPathComponent("Blank")
        try fm.createDirectory(at: blankRoot, withIntermediateDirectories: true)
        png(image([]), blankRoot.appendingPathComponent("blank.png"))
        let blankIndex = PersistentDocumentIndex(databaseURL: base.appendingPathComponent("BlankIndex/Documents.sqlite"))
        let blank = try blankIndex.synchronize(roots: [blankRoot])
        precondition(blank.files == 1 && blank.searchable == 0 && blank.unfinished == 0 && blank.ocrPages == 1, "A successful OCR request that finds no text is not a failed scan")
        let legacyURL = base.appendingPathComponent("LegacyIndex/Documents.sqlite")
        let legacyIndex = PersistentDocumentIndex(databaseURL: legacyURL)
        _ = try legacyIndex.synchronize(roots: [legacyRoot])
        var handle: OpaquePointer?; precondition(sqlite3_open(legacyURL.path, &handle) == SQLITE_OK)
        precondition(sqlite3_exec(handle, "ALTER TABLE documents DROP COLUMN extraction; DROP TABLE document_pages; PRAGMA user_version=1;", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(handle)
        try check(legacyIndex.search(query: "LEGACYMARKER", roots: [legacyRoot]).items.count == 1)
        let migrated = try legacyIndex.synchronize(roots: [legacyRoot])
        precondition(migrated.reused == 1 && migrated.extracted == 0)
        try check(legacyIndex.search(query: "LEGACYMARKER", roots: [legacyRoot]).items.count == 1)
        let tiny = PersistentDocumentIndex(databaseURL: base.appendingPathComponent("Tiny/Documents.sqlite"), limitBytes: 131_072)
        try "容量測試".write(to: legacyRoot.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)
        let cap = try tiny.synchronize(roots: [legacyRoot]); precondition(cap.capped)
        let measurement = try index.statistics(roots: [root])
        print("Synthetic OCR index: \(measurement.files) files, \(measurement.ocrPages) OCR pages, \(measurement.bytes) bytes (includes FTS, page text and SQLite journals)")
        try index.retain(roots: []); precondition(!fm.fileExists(atPath: database.path))
        print("PASS: actual Apple Vision Chinese/English OCR, cross-script snippets, mixed PDF page numbers, bounded batches/resume, cancellation, no-op reuse, OCR disable/enable, replacement/deletion, scope isolation, cloud-only policy and six-folder presets; generated synthetic images/PDFs only")
    }
}
