import HanSearchCore

extension SearchStore {
    var selectedPreviewItem: SearchItem? {
        guard composerMode == nil, details == nil, !isAppBrowser,
              let selection, primaryResultIDs.contains(selection),
              let item = results.first(where: { $0.id == selection }), !item.isApplication, item.url.isFileURL else { return nil }
        return item
    }
    func previewFile(_ item: SearchItem) {
        selection = item.id; previewSelectionArmed = true
        toggleFilePreview?()
    }
    func movePreviewSelection(_ offset: Int) {
        let candidates = primaryResultIDs.compactMap { id in results.first { $0.id == id && !$0.isApplication && $0.url.isFileURL } }
        guard !candidates.isEmpty else { return }
        let index = candidates.firstIndex { $0.id == selection } ?? 0
        selection = candidates[min(max(index + offset, 0), candidates.count - 1)].id
        previewSelectionArmed = true
    }
}
