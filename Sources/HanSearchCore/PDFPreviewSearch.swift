import Foundation
import PDFKit
import CoreGraphics

public struct PDFPreviewPageMatch: Sendable {
    public let pageIndex: Int
    public let ranges: [NSRange]
    public let rectangles: [CGRect]
    public init(pageIndex: Int, ranges: [NSRange] = [], rectangles: [CGRect] = []) {
        self.pageIndex = pageIndex; self.ranges = ranges; self.rectangles = rectangles
    }
}

public struct PDFPreviewMatches: Sendable {
    public let pages: [PDFPreviewPageMatch]
    public let limited: Bool
}

public enum FilePreviewError: String, Error, LocalizedError {
    case unavailable = "無法讀取預覽，檔案可能已移動或沒有取用權限。"
    case locked = "PDF 已加密，請使用原本的 App 解鎖後查看。"
    case tooLarge = "PDF 超過 200 MB，請使用原本的 App 開啟。"
    case cloudOnly = "檔案尚未下載，請先在 Finder 下載後再預覽。"
    public var errorDescription: String? { rawValue }
}

/// Works on an independent PDFDocument, never shared with the on-screen PDFView.
/// All offsets remain in the original text; no source file is changed or written.
public enum PDFPreviewSearch {
    public static func validate(_ url: URL) throws {
        guard url.isFileURL, let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
              values.isRegularFile == true else { throw FilePreviewError.unavailable }
        if CloudFileAvailability.needsDownload(isUbiquitous: values.isUbiquitousItem == true, status: values.ubiquitousItemDownloadingStatus) { throw FilePreviewError.cloudOnly }
        if url.pathExtension.lowercased() == "pdf", (values.fileSize ?? 0) > 200_000_000 { throw FilePreviewError.tooLarge }
    }

    public static func nativeMatches(_ url: URL, query: String, preferredPages: [Int], cancellation: ProcessCancellation) throws -> PDFPreviewMatches {
        try validate(url)
        guard !cancellation.isCancelled else { throw CancellationError() }
        guard let document = PDFDocument(url: url) else { throw FilePreviewError.unavailable }
        guard !document.isLocked else { throw FilePreviewError.locked }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return PDFPreviewMatches(pages: [], limited: false) }
        let count = min(document.pageCount, 2_000)
        let preferred = Array(Set(preferredPages.filter { $0 > 0 && $0 <= count }.map { $0 - 1 })).sorted()
        let preferredSet = Set(preferred)
        let order = preferred + (0..<count).filter { !preferredSet.contains($0) }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        var matches: [PDFPreviewPageMatch] = [], highlights = 0
        var limited = count < document.pageCount
        for index in order {
            guard !cancellation.isCancelled else { throw CancellationError() }
            if ProcessInfo.processInfo.systemUptime >= deadline || highlights >= 500 { limited = true; break }
            let text = document.page(at: index)?.string ?? ""
            if text.utf8.count > 500_000 { limited = true; continue }
            let all = SearchHighlight.ranges(in: text, query: query)
            let ranges = Array(all.prefix(min(100, 500 - highlights)))
            limited = limited || ranges.count < all.count
            if !ranges.isEmpty { matches.append(PDFPreviewPageMatch(pageIndex: index, ranges: ranges)); highlights += ranges.count }
        }
        guard !cancellation.isCancelled else { throw CancellationError() }
        return PDFPreviewMatches(pages: matches.sorted { $0.pageIndex < $1.pageIndex }, limited: limited)
    }

    /// Locate only the visible indexed OCR page. Raster coordinates are mapped back
    /// through the PDF drawing transform, including crop origins and page rotation.
    public static func ocrMatch(_ url: URL, pageIndex: Int, query: String, cancellation: ProcessCancellation,
                                shouldDefer: @escaping @Sendable () -> Bool = { false }) throws -> PDFPreviewPageMatch {
        try validate(url)
        guard !cancellation.isCancelled else { throw CancellationError() }
        guard !shouldDefer() else { throw DocumentReadReason.ocrDeferred }
        guard let document = PDFDocument(url: url), !document.isLocked,
              let page = document.page(at: pageIndex), let ref = page.pageRef else { throw FilePreviewError.unavailable }
        let box = page.bounds(for: .cropBox), dimension = max(box.width, box.height)
        guard dimension.isFinite, dimension > 0 else { throw FilePreviewError.unavailable }
        let scale = min(3, 1_800 / dimension)
        let width = max(1, Int(ceil(box.width * scale))), height = max(1, Int(ceil(box.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw FilePreviewError.unavailable }
        let drawing = ref.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.concatenate(drawing); context.drawPDFPage(ref)
        guard let image = context.makeImage() else { throw FilePreviewError.unavailable }
        let observations = try VisionTextRecognizer.observations(image, cancellation: cancellation, shouldDefer: shouldDefer)
        var rectangles: [CGRect] = []
        for observation in observations {
            guard !cancellation.isCancelled else { throw CancellationError() }
            guard let candidate = observation.topCandidates(1).first else { continue }
            for match in SearchHighlight.ranges(in: candidate.string, query: query).prefix(100) {
                guard let range = Range(match, in: candidate.string), let bounds = try? candidate.boundingBox(for: range)?.boundingBox else { continue }
                let pixels = CGRect(x: bounds.minX * CGFloat(width), y: bounds.minY * CGFloat(height),
                                    width: bounds.width * CGFloat(width), height: bounds.height * CGFloat(height))
                let rect = pixels.applying(drawing.inverted()).intersection(box)
                if !rect.isNull && !rect.isEmpty { rectangles.append(rect) }
                if rectangles.count >= 100 { break }
            }
            if rectangles.count >= 100 { break }
        }
        return PDFPreviewPageMatch(pageIndex: pageIndex, rectangles: rectangles)
    }
}
