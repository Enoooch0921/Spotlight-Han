import HanSearchCore

extension SearchStore {
    var selectedPreviewItem: SearchItem? {
        guard diagnosticURL == nil, composerMode == nil, details == nil, !isAppBrowser,
              let selection, let item = results.first(where: { $0.id == selection }),
              !item.isApplication, item.url.isFileURL,
              showOtherIndexedResults || !isOtherIndexedResult(item) else { return nil }
        return item
    }
    func previewFile(_ item: SearchItem) {
        selection = item.id; previewSelectionArmed = true
        toggleFilePreview?()
    }
    func movePreviewSelection(_ offset: Int) {
        let files = Set(results.lazy.filter { !$0.isApplication && $0.url.isFileURL }.map(\.id))
        let candidates = primaryResultIDs.filter(files.contains)
        guard !candidates.isEmpty else { return }
        let index = candidates.firstIndex { $0 == selection } ?? 0
        selection = candidates[min(max(index + offset, 0), candidates.count - 1)]
        previewSelectionArmed = true
    }
}
