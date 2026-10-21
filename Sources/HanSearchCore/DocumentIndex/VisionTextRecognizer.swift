import Foundation
import Vision
import ImageIO
import CoreGraphics

/// One bounded, cancellable on-device request at a time. No images are persisted or uploaded.
enum VisionTextRecognizer {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "webp", "bmp"]
    static let maxDimension = 2400
    static func image(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, CGImageSourceGetPrimaryImageIndex(source),
                [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                 kCGImageSourceThumbnailMaxPixelSize: maxDimension, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw DocumentReadReason.readFailed }
        return image
    }
    static func recognize(_ image: CGImage, cancellation: ProcessCancellation, shouldDefer: @escaping @Sendable () -> Bool = { false }) throws -> String {
        guard !cancellation.isCancelled else { throw CancellationError() }
        let request = VNRecognizeTextRequest()
        request.preferBackgroundProcessing = true
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        let languages = ["zh-Hant", "zh-Hans", "en-US"].filter { supported.contains($0) }
        guard languages.contains("zh-Hant"), languages.contains("zh-Hans") else { throw DocumentReadReason.ocrUnavailable }
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = false
        let deferred = ProcessCancellation()
        let deadline = Date().addingTimeInterval(20)
        let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "local.hansearch.ocr-watchdog"))
        watchdog.schedule(deadline: .now(), repeating: .milliseconds(100))
        watchdog.setEventHandler {
            if shouldDefer() { deferred.cancel() }
            if cancellation.isCancelled || deferred.isCancelled || Date() >= deadline { request.cancel() }
        }
        watchdog.resume(); defer { watchdog.cancel() }
        do { try VNImageRequestHandler(cgImage: image).perform([request]) }
        catch {
            if cancellation.isCancelled { throw CancellationError() }
            if deferred.isCancelled || shouldDefer() { throw DocumentReadReason.ocrDeferred }
            throw Date() >= deadline ? DocumentReadReason.ocrTimedOut : DocumentReadReason.ocrFailed
        }
        guard !cancellation.isCancelled else { throw CancellationError() }
        guard !deferred.isCancelled && !shouldDefer() else { throw DocumentReadReason.ocrDeferred }
        guard Date() < deadline else { throw DocumentReadReason.ocrTimedOut }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
