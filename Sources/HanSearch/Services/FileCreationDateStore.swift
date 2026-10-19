import Foundation
import HanSearchCore

/// Read only visible results' filesystem metadata, off the UI thread.
actor FileCreationDateStore {
    static let shared = FileCreationDateStore()
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "local.hansearch.file-dates"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private struct Entry { let date: Date?; let readAt: Date }
    private var cache: [URL: Entry] = [:]

    func date(for url: URL) async -> Date? {
        guard url.isFileURL, !Task.isCancelled else { return nil }
        if let cached = cache[url], Date().timeIntervalSince(cached.readAt) < 60 { return cached.date }
        let cancellation = ProcessCancellation()
        let date: Date? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                Self.queue.addOperation {
                    guard !cancellation.isCancelled else { continuation.resume(returning: nil); return }
                    // A fresh URL avoids URLResourceValues retained by an earlier read.
                    let values = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.creationDateKey])
                    continuation.resume(returning: values?.creationDate)
                }
            }
        } onCancel: { cancellation.cancel() }
        guard !Task.isCancelled else { return nil }
        cache[url] = Entry(date: date, readAt: Date())
        if cache.count > 512, let oldest = cache.min(by: { $0.value.readAt < $1.value.readAt })?.key { cache[oldest] = nil }
        return date
    }
}
