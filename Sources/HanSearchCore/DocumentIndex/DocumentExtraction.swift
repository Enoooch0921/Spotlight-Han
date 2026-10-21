import Foundation
import PDFKit
import CoreGraphics

struct IndexedPage: Sendable {
    let number: Int
    let text: String
    let isOCR: Bool
    var issue: DocumentReadReason? = nil
}
struct DocumentExtraction {
    let pages: [IndexedPage]
    let reason: DocumentReadReason?
    var text: String { pages.map(\.text).joined(separator: "\n") }
    static func read(_ url: URL, cached: [IndexedPage], ocrEnabled: Bool, scheduler: OCRWorkScheduler?, cancellation: ProcessCancellation,
                     pageProgress: (Int, Int, Bool) -> Void) throws -> DocumentExtraction {
        if VisionTextRecognizer.imageExtensions.contains(url.pathExtension.lowercased()) {
            guard ocrEnabled else { return DocumentExtraction(pages: [], reason: .ocrDisabled) }
            try scheduler?.prepare(cancellation: cancellation)
            pageProgress(1, 1, true)
            let text = try autoreleasepool { try VisionTextRecognizer.recognize(VisionTextRecognizer.image(url), cancellation: cancellation, shouldDefer: { scheduler?.shouldDefer ?? false }) }
            return DocumentExtraction(pages: [IndexedPage(number: 1, text: text, isOCR: true)], reason: nil)
        }
        guard url.pathExtension.lowercased() == "pdf" else {
            return DocumentExtraction(pages: [IndexedPage(number: 0, text: try IndexedDocumentText.read(url, cancellation: cancellation), isOCR: false)], reason: nil)
        }
        guard let pdf = PDFDocument(url: url) else { throw DocumentReadReason.readFailed }
        guard !pdf.isLocked else { throw DocumentReadReason.locked }
        guard pdf.pageCount <= 2000 else { throw DocumentReadReason.indexWorkLimit }
        var pages = cached, bytes = cached.reduce(0) { $0 + $1.text.utf8.count }, ocrCount = 0
        let deadline = Date().addingTimeInterval(10)
        var reason: DocumentReadReason? = cached.compactMap(\.issue).first
        for index in cached.count..<pdf.pageCount {
            guard !cancellation.isCancelled else { throw CancellationError() }
            if ocrCount >= 8 || Date() > deadline { return DocumentExtraction(pages: pages, reason: .ocrPending) }
            do {
                let page: IndexedPage = try autoreleasepool {
                    guard let page = pdf.page(at: index) else { throw DocumentReadReason.readFailed }
                    let text = page.string ?? ""
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        pageProgress(index + 1, pdf.pageCount, false)
                        return IndexedPage(number: index + 1, text: text, isOCR: false)
                    }
                    guard ocrEnabled else { throw DocumentReadReason.ocrDisabled }
                    try scheduler?.prepare(cancellation: cancellation)
                    pageProgress(index + 1, pdf.pageCount, true)
                    ocrCount += 1
                    return IndexedPage(number: index + 1, text: try VisionTextRecognizer.recognize(render(page), cancellation: cancellation, shouldDefer: { scheduler?.shouldDefer ?? false }), isOCR: true)
                }
                bytes += page.text.utf8.count
                guard bytes <= 8_000_000 else { return DocumentExtraction(pages: pages, reason: .indexFileTextLimit) }
                pages.append(page)
            } catch is CancellationError { throw CancellationError() }
            catch DocumentReadReason.ocrDeferred { return DocumentExtraction(pages: pages, reason: .ocrDeferred) }
            catch {
                // Keep other readable pages, while clearly distinguishing a partial document.
                reason = error as? DocumentReadReason ?? .readFailed
                pages.append(IndexedPage(number: index + 1, text: "", isOCR: false, issue: reason))
            }
        }
        return DocumentExtraction(pages: pages, reason: reason ?? (pages.allSatisfy { $0.text.isEmpty } && !pages.contains(where: \.isOCR) ? .noText : nil))
    }
    private static func render(_ page: PDFPage) throws -> CGImage {
        guard let ref = page.pageRef else { throw DocumentReadReason.readFailed }
        let box = page.bounds(for: .cropBox), size = max(box.width, box.height)
        guard size.isFinite, size > 0 else { throw DocumentReadReason.readFailed }
        let scale = min(3, CGFloat(VisionTextRecognizer.maxDimension) / size)
        let width = max(1, Int(ceil(box.width * scale))), height = max(1, Int(ceil(box.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw DocumentReadReason.ocrFailed }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.concatenate(ref.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(ref)
        guard let image = context.makeImage() else { throw DocumentReadReason.ocrFailed }; return image
    }
}
