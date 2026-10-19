import Foundation
import PDFKit

/// Ephemeral, bounded excerpts for document results returned by the system index.
public enum DocumentPreview: Sendable, Equatable {
    case match(String)
    case noLiteralMatch
    case unavailable(DocumentReadReason)
    case limited
    case cancelled

    public static func read(_ url: URL, query: String, cancellation: ProcessCancellation) -> DocumentPreview {
        guard !cancellation.isCancelled else { return .cancelled }
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            guard values.isRegularFile == true else { return .unavailable(.readFailed) }
            guard (values.fileSize ?? 0) <= 20_000_000 else { return .unavailable(.tooLarge) }
            if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded { return .unavailable(.cloudOnly) }
            func excerpt(_ text: String) -> DocumentPreview {
                guard !cancellation.isCancelled else { return .cancelled }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .unavailable(.noText) }
                let snippet = SearchHighlight.excerpt(in: text, query: query, limit: 220)
                return SearchHighlight.ranges(in: snippet, query: query).isEmpty ? .noLiteralMatch : .match(snippet)
            }
            if url.pathExtension.lowercased() == "pdf" {
                guard let pdf = PDFDocument(url: url) else { return .unavailable(.readFailed) }
                guard !pdf.isLocked else { return .unavailable(.locked) }
                let deadline = Date().addingTimeInterval(3)
                var hasText = false, bytes = 0
                for index in 0..<min(pdf.pageCount, 500) {
                    guard !cancellation.isCancelled else { return .cancelled }
                    guard Date() < deadline else { return .limited }
                    let text = pdf.page(at: index)?.string ?? ""
                    bytes += text.utf8.count
                    guard bytes <= 8_000_000 else { return .limited }
                    hasText = hasText || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if case let .match(snippet) = excerpt(text) { return .match(snippet) }
                }
                if pdf.pageCount > 500 { return .limited }
                return hasText ? .noLiteralMatch : .unavailable(.noText)
            }
            let text = try SearchService.extractText(url, cancellation: cancellation)
            guard !cancellation.isCancelled else { return .cancelled }
            guard text.utf8.count <= 8_000_000 else { return .limited }
            return excerpt(text)
        } catch is CancellationError { return .cancelled }
        catch { return .unavailable(error as? DocumentReadReason ?? .readFailed) }
    }
}
