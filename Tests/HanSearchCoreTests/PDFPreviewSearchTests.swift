import Foundation
import CoreGraphics
import CoreText
import PDFKit
import HanSearchCore

extension ChineseSearchTests {
    func testPDFPreviewSearch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HanPreview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func line(_ text: String, into context: CGContext, at point: CGPoint, size: CGFloat = 34) {
            context.textPosition = point
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: CTFontCreateWithName("PingFangTC-Regular" as CFString, size, nil), .foregroundColor: CGColor(gray: 0, alpha: 1)
            ])), context)
        }
        let native = root.appendingPathComponent("native.pdf")
        var box = CGRect(x: 0, y: 0, width: 800, height: 600)
        let context = CGContext(native as CFURL, mediaBox: &box, nil)!
        for text in ["First page without a match", "漢字搜尋定位 保固證明", "汉字搜寻定位 保固证明"] {
            context.beginPDFPage(nil); line(text, into: context, at: CGPoint(x: 60, y: 400)); context.endPDFPage()
        }; context.closePDF()
        let before = try Data(contentsOf: native)
        let matches = try PDFPreviewSearch.nativeMatches(native, query: "汉字搜寻定位", preferredPages: [2, 0, 999], cancellation: ProcessCancellation())
        precondition(matches.pages.map(\.pageIndex) == [1, 2] && !matches.limited)
        let document = PDFDocument(url: native)!
        for page in matches.pages {
            let selection = document.page(at: page.pageIndex)!.selection(for: page.ranges[0])!
            precondition(ChineseSearch.normalized(selection.string ?? "").contains("汉字搜寻定位"), "Ranges must address original PDF text")
        }
        let absent = try PDFPreviewSearch.nativeMatches(native, query: "absent-marker", preferredPages: [], cancellation: ProcessCancellation())
        precondition(absent.pages.isEmpty)
        let cancelled = ProcessCancellation(); cancelled.cancel()
        do { _ = try PDFPreviewSearch.nativeMatches(native, query: "保固", preferredPages: [], cancellation: cancelled); preconditionFailure("Cancelled preview must stop") }
        catch is CancellationError { }

        let imageContext = CGContext(data: nil, width: 1600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        imageContext.setFillColor(CGColor(gray: 1, alpha: 1)); imageContext.fill(CGRect(x: 0, y: 0, width: 1600, height: 400))
        line("保固證明 WARRANTY DL32", into: imageContext, at: CGPoint(x: 80, y: 230), size: 72)
        let bitmap = imageContext.makeImage()!
        let scan = root.appendingPathComponent("scan.pdf")
        let scanContext = CGContext(scan as CFURL, mediaBox: &box, nil)!
        scanContext.beginPDFPage(nil); scanContext.draw(bitmap, in: CGRect(x: 80, y: 200, width: 640, height: 160)); scanContext.endPDFPage(); scanContext.closePDF()
        let scanBefore = try Data(contentsOf: scan)
        let ocr = try PDFPreviewSearch.ocrMatch(scan, pageIndex: 0, query: "保固", cancellation: ProcessCancellation())
        precondition(!ocr.rectangles.isEmpty, "Actual Vision OCR must locate the Chinese query")
        precondition(ocr.rectangles.allSatisfy { CGRect(x: 75, y: 195, width: 650, height: 170).contains($0) }, "OCR coordinates must map back to PDF page space")
        do { _ = try PDFPreviewSearch.ocrMatch(scan, pageIndex: 0, query: "保固", cancellation: ProcessCancellation(), shouldDefer: { true }); preconditionFailure("Protected work must defer OCR") }
        catch DocumentReadReason.ocrDeferred { }
        let nativeAfter = try Data(contentsOf: native), scanAfter = try Data(contentsOf: scan)
        precondition(nativeAfter == before && scanAfter == scanBefore, "Previews must never write either PDF")
        print("PASS: PDF original-text ranges, cross-script matches, actual page indices, absent query, cancellation, on-device scan OCR coordinates, work deferral and unchanged source bytes; synthetic PDFs only")
    }
}
