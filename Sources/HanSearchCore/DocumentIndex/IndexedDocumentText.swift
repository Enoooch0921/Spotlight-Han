import Foundation
import PDFKit

/// The persistent index does not use Spotlight's legacy extractors.
enum IndexedDocumentText {
    static func read(_ url: URL, cancellation: ProcessCancellation) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ["ppt", "pps", "pot"].contains(ext) { throw DocumentReadReason.legacyNeedsSystemIndex }
        guard ext == "pdf" else { return try SearchService.extractText(url, cancellation: cancellation) }
        guard let pdf = PDFDocument(url: url) else { throw DocumentReadReason.readFailed }
        guard !pdf.isLocked else { throw DocumentReadReason.locked }
        guard pdf.pageCount <= 2000 else { throw DocumentReadReason.indexWorkLimit }
        var text = "", bytes = 0
        let deadline = Date().addingTimeInterval(10)
        for page in 0..<pdf.pageCount {
            if cancellation.isCancelled { throw CancellationError() }
            guard Date() < deadline else { throw DocumentReadReason.indexWorkLimit }
            if let value = pdf.page(at: page)?.string {
                bytes += value.utf8.count + 1
                guard bytes <= 8_000_000 else { throw DocumentReadReason.indexFileTextLimit }
                text += value + "\n"
            }
        }
        return text
    }
}
