import AppKit
import PDFKit
import HanSearchCore

private final class PreviewPDFDocument: @unchecked Sendable {
    let document: PDFDocument
    init(_ document: PDFDocument) { self.document = document }
}

/// Serializes file decoding/search so rapidly browsing results cannot launch many
/// simultaneous PDF reads. Cancellation is checked before queued work starts.
enum PreviewReadQueue {
    private static let queue: OperationQueue = {
        let queue = OperationQueue(); queue.name = "local.hansearch.quick-preview"
        queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .userInitiated
        return queue
    }()
    static func run<T: Sendable>(cancellation: ProcessCancellation, _ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.addOperation {
                    do {
                        guard !cancellation.isCancelled else { throw CancellationError() }
                        let result = try work()
                        guard !cancellation.isCancelled else { throw CancellationError() }
                        continuation.resume(returning: result)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }
}

@MainActor
final class PDFQuickPreviewSession {
    let view = PDFView()
    var changed: ((String, Bool, Int, Int, [Int]) -> Void)?
    var failed: ((String) -> Void)?
    var shouldDeferOCR: @Sendable () -> Bool = { false }
    private(set) var hitPages: [Int] = []
    private var request: FilePreviewRequest?
    private var generation = UUID()
    private var loadTask: Task<Void, Never>?, searchTask: Task<Void, Never>?, ocrTask: Task<Void, Never>?
    private var loadCancellation = ProcessCancellation(), searchCancellation = ProcessCancellation(), ocrCancellation = ProcessCancellation()
    private var nativeMatches: [PDFPreviewPageMatch] = []
    private var locatedOCR = Set<Int>()
    private var annotations: [Int: [PDFAnnotation]] = [:]
    private var pageObserver: NSObjectProtocol?
    private var status = "", ocrStatus = ""
    private var currentIndex: Int { guard let page = view.currentPage, let doc = view.document else { return 0 }; return doc.index(for: page) }

    init() {
        view.autoScales = true; view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical; view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        pageObserver = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: view, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pageChanged() }
        }
    }
    deinit { if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) }; loadCancellation.cancel(); searchCancellation.cancel(); ocrCancellation.cancel() }

    func open(_ request: FilePreviewRequest) {
        close(); self.request = request
        let token = generation, cancellation = loadCancellation
        status = "正在載入 PDF…"; report()
        loadTask = Task { [weak self] in
            do {
                let loaded = try await PreviewReadQueue.run(cancellation: cancellation) {
                    try PDFPreviewSearch.validate(request.url)
                    guard let document = PDFDocument(url: request.url) else { throw FilePreviewError.unavailable }
                    guard !document.isLocked else { throw FilePreviewError.locked }
                    return PreviewPDFDocument(document)
                }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.loadTask = nil; self.view.document = loaded.document
                self.hitPages = Array(Set(request.pages.filter { $0 > 0 && $0 <= loaded.document.pageCount })).sorted()
                if let page = loaded.document.page(at: (self.hitPages.first ?? 1) - 1) { self.view.go(to: page) }
                self.status = "正在標示命中文字…"; self.report()
                self.search(request, generation: token)
                self.locateCurrentOCRPage()
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.loadTask = nil; self.failed?(L.text(error.localizedDescription))
            }
        }
        report()
    }
    func close() {
        generation = UUID(); loadTask?.cancel(); searchTask?.cancel(); ocrTask?.cancel()
        loadTask = nil; searchTask = nil; ocrTask = nil
        loadCancellation.cancel(); searchCancellation.cancel(); ocrCancellation.cancel()
        loadCancellation = ProcessCancellation(); searchCancellation = ProcessCancellation(); ocrCancellation = ProcessCancellation()
        request = nil; view.document = nil; view.highlightedSelections = []
        nativeMatches = []; locatedOCR = []; annotations = [:]; hitPages = []; status = ""; ocrStatus = ""
    }
    private func search(_ request: FilePreviewRequest, generation token: UUID) {
        let cancellation = searchCancellation
        searchTask = Task { [weak self] in
            do {
                let result = try await PreviewReadQueue.run(cancellation: cancellation) {
                    try PDFPreviewSearch.nativeMatches(request.url, query: request.query, preferredPages: request.pages, cancellation: cancellation)
                }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.searchTask = nil; self.nativeMatches = result.pages
                self.hitPages = Array(Set(self.hitPages + result.pages.map { $0.pageIndex + 1 })).sorted()
                self.view.highlightedSelections = result.pages.flatMap { match in
                    guard let page = self.view.document?.page(at: match.pageIndex) else { return [PDFSelection]() }
                    let length = (page.string ?? "").utf16.count
                    return match.ranges.compactMap { range in
                        // The file may have changed between viewer loading and the independent search.
                        guard range.location != NSNotFound, NSMaxRange(range) <= length else { return nil }
                        let selection = page.selection(for: range)
                        selection?.color = NSColor.systemYellow.withAlphaComponent(0.5)
                        return selection
                    }
                }
                if request.pages.isEmpty, let first = result.pages.first { self.go(to: first.pageIndex + 1) }
                else { self.scrollToMatch(on: self.currentIndex) }
                self.status = result.limited ? "已標示部分命中；大型 PDF 的預覽搜尋有讀取上限。" : result.pages.isEmpty ? "未找到可標示的文字；可繼續翻頁查看。" : "已標示繁簡相符的搜尋文字"
                self.report(); self.locateCurrentOCRPage()
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.searchTask = nil; self.status = "內文標示未完成，仍可翻閱 PDF。"; self.report()
            }
        }
        report()
    }
    func go(to pageNumber: Int) {
        guard let document = view.document, pageNumber > 0, let page = document.page(at: pageNumber - 1) else { return }
        view.go(to: page); scrollToMatch(on: pageNumber - 1); pageChanged()
    }
    func moveHit(_ direction: Int) {
        let current = currentIndex + 1
        let target = direction > 0 ? hitPages.first(where: { $0 > current }) ?? hitPages.first : hitPages.last(where: { $0 < current }) ?? hitPages.last
        if let target { go(to: target) }
    }
    private func scrollToMatch(on index: Int) {
        if let match = nativeMatches.first(where: { $0.pageIndex == index }), let range = match.ranges.first,
           let page = view.document?.page(at: index), range.location != NSNotFound,
           NSMaxRange(range) <= (page.string ?? "").utf16.count,
           let selection = page.selection(for: range) { view.go(to: selection) }
    }
    private func pageChanged() {
        report(); locateCurrentOCRPage()
    }
    private func locateCurrentOCRPage() {
        guard let request, request.isOCR, let page = view.currentPage else { return }
        let index = currentIndex
        guard request.pages.contains(index + 1), !locatedOCR.contains(index), (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if shouldDeferOCR() { ocrStatus = "OCR 定位已暫停，工作保護或節能條件解除後可重新預覽。"; report(); return }
        guard ocrTask == nil else { return }
        let cancellation = ocrCancellation, token = generation, deferOCR = shouldDeferOCR
        ocrStatus = "正在定位這一頁的 OCR 文字…"; report()
        ocrTask = Task { [weak self] in
            do {
                let match = try await PreviewReadQueue.run(cancellation: cancellation) {
                    try PDFPreviewSearch.ocrMatch(request.url, pageIndex: index, query: request.query, cancellation: cancellation, shouldDefer: deferOCR)
                }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.ocrTask = nil; self.locatedOCR.insert(index)
                if let page = self.view.document?.page(at: index) {
                    self.annotations[index] = match.rectangles.map { rect in
                        let annotation = PDFAnnotation(bounds: rect, forType: .square, withProperties: nil)
                        annotation.color = .clear; annotation.interiorColor = NSColor.systemYellow.withAlphaComponent(0.35)
                        annotation.border = PDFBorder(); annotation.border?.lineWidth = 0; annotation.shouldPrint = false
                        page.addAnnotation(annotation); return annotation
                    }
                    self.view.needsDisplay = true
                }
                self.ocrStatus = match.rectangles.isEmpty ? "已跳到索引命中頁；這次未能定位 OCR 文字。" : "已標示 OCR 文字位置（辨識可能有誤差）"
                self.report(); if self.currentIndex != index { self.locateCurrentOCRPage() }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.ocrTask = nil
                self.ocrStatus = (error as? DocumentReadReason) == .ocrDeferred ? "OCR 定位已暫停，工作保護或節能條件解除後可重新預覽。" : "已跳到索引命中頁；OCR 定位未完成。"
                self.report()
            }
        }
        report()
    }
    private func report() {
        changed?(ocrStatus.isEmpty ? status : ocrStatus, loadTask != nil || searchTask != nil || ocrTask != nil,
                 currentIndex + 1, view.document?.pageCount ?? 0, hitPages)
    }
}
