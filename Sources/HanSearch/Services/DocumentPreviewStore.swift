import Foundation
import HanSearchCore

actor DocumentPreviewStore {
    static let shared = DocumentPreviewStore()
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "local.hansearch.document-previews"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private struct Key: Hashable, Sendable { let url: URL; let query: String }
    private struct Entry { let value: DocumentPreview; let time: Date }
    private var cache: [Key: Entry] = [:]

    func preview(url: URL, query: String) async -> DocumentPreview {
        guard !Task.isCancelled else { return .cancelled }
        let key = Key(url: url, query: String(query.prefix(200)))
        if let cached = cache[key], Date().timeIntervalSince(cached.time) < 60 { return cached.value }
        let cancellation = ProcessCancellation()
        let value: DocumentPreview = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Self.queue.addOperation {
                    continuation.resume(returning: DocumentPreview.read(url, query: key.query, cancellation: cancellation))
                }
            }
        } onCancel: { cancellation.cancel() }
        guard !Task.isCancelled, value != .cancelled else { return .cancelled }
        cache[key] = Entry(value: value, time: Date())
        if cache.count > 100, let oldest = cache.min(by: { $0.value.time < $1.value.time })?.key { cache[oldest] = nil }
        return value
    }
}
