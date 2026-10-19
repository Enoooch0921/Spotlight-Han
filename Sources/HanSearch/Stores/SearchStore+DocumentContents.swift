import Foundation
import HanSearchCore

extension SearchStore {
    func cacheDocumentFilenameMatches() {
        documentFilenameMatches = Set(results.filter { $0.source == "文件・系統索引" && ChineseSearch.matches($0.name, query: query) }.map(\.id))
    }
    func isOtherIndexedResult(_ item: SearchItem) -> Bool {
        guard item.source == "文件・系統索引", item.excerpt.isEmpty else { return false }
        if case .match = documentPreviews[item.id] { return false }
        // Literal filename matches are useful even if the native index cannot expose body text.
        return !documentFilenameMatches.contains(item.id)
    }
    var otherIndexedResultCount: Int { results.filter { isOtherIndexedResult($0) }.count }
    func toggleOtherIndexedResults() {
        showOtherIndexedResults.toggle()
        if !allIDs.contains(selection ?? "") { selection = allIDs.first(where: { $0 != "quick:web" }) ?? allIDs.first }
        onLayoutChanged?()
    }
    func resetDocumentVerification() {
        documentVerificationTask?.cancel(); documentVerificationTask = nil
        documentVerificationGeneration = UUID(); documentVerificationQuery = ""; documentVerificationStarted = Date()
        documentPreviews = [:]; documentFilenameMatches = []; verifyingDocumentContents = false; showOtherIndexedResults = false
    }
    func resetDocumentVerificationIfNeeded(query: String) {
        if query != documentVerificationQuery || Date().timeIntervalSince(documentVerificationStarted) >= 60 || ![SearchMode.all, .contents].contains(mode) || composerMode != nil {
            resetDocumentVerification(); documentVerificationQuery = query
        }
    }
    func verifyDocumentContents(query: String) {
        documentVerificationTask?.cancel()
        let token = UUID(); documentVerificationGeneration = token; documentVerificationQuery = query
        let items = results.filter { $0.source == "文件・系統索引" && $0.excerpt.isEmpty && documentPreviews[$0.id] == nil }
        guard !items.isEmpty else { verifyingDocumentContents = false; return }
        verifyingDocumentContents = true
        let loader = documentPreviewLoader
        // Inspect candidates independently of scroll position. Only two reads run at once.
        documentVerificationTask = Task { [weak self] in
            await withTaskGroup(of: (String, DocumentPreview).self) { group in
                var iterator = items.makeIterator()
                var batch: [String: DocumentPreview] = [:]
                func enqueue(_ item: SearchItem) { group.addTask { (item.id, await loader(item.url, query)) } }
                for _ in 0..<2 { if let item = iterator.next() { enqueue(item) } }
                while let (id, preview) = await group.next() {
                    guard !Task.isCancelled, let self, self.documentVerificationGeneration == token else { group.cancelAll(); return }
                    if preview != .cancelled { batch[id] = preview }
                    let confirmed: Bool = { if case .match = preview { return true }; return false }()
                    if confirmed || batch.count >= 4 {
                        self.documentPreviews.merge(batch) { _, new in new }; batch.removeAll()
                        if confirmed && !self.allIDs.contains(self.selection ?? "") { self.selection = self.allIDs.first(where: { $0 != "quick:web" }) ?? self.allIDs.first }
                        self.onLayoutChanged?()
                    }
                    if let item = iterator.next() { enqueue(item) }
                }
                if !batch.isEmpty, !Task.isCancelled, let self, self.documentVerificationGeneration == token {
                    self.documentPreviews.merge(batch) { _, new in new }
                }
            }
            guard !Task.isCancelled, let self, self.documentVerificationGeneration == token else { return }
            self.verifyingDocumentContents = false; self.documentVerificationTask = nil
            self.onLayoutChanged?()
        }
    }
}
