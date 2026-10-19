import Foundation
import HanSearchCore

extension SearchStore {
    var canSortFileResults: Bool {
        [.names, .videos, .contents].contains(mode) || mode == .all && results.contains { !$0.isApplication }
    }

    func refreshFileDates() {
        fileDatesTask?.cancel(); fileDatesTask = nil
        let token = UUID(); fileDatesGeneration = token
        let items = results.filter { !$0.isApplication }
        let paths = Set(items.map(\.id))
        fileDates = fileDates.filter { paths.contains($0.key) }
        guard fileSort != .relevance, canSortFileResults, !items.isEmpty, composerMode == nil else {
            readingFileDates = false; return
        }
        readingFileDates = true
        let loader = fileCreationDateLoader
        // Resolve dates for all current candidates, not only visible rows, before sorting.
        fileDatesTask = Task { [weak self] in
            var dates: [String: Date] = [:]
            await withTaskGroup(of: (String, Date?).self) { group in
                var iterator = items.makeIterator()
                func enqueue(_ item: SearchItem) { group.addTask { (item.id, await loader(item.url)) } }
                for _ in 0..<2 { if let item = iterator.next() { enqueue(item) } }
                while let (id, date) = await group.next() {
                    guard !Task.isCancelled, let self, self.fileDatesGeneration == token else { group.cancelAll(); return }
                    if let date { dates[id] = date }
                    if let item = iterator.next() { enqueue(item) }
                }
            }
            guard !Task.isCancelled, let self, self.fileDatesGeneration == token else { return }
            self.fileDates = dates; self.readingFileDates = false; self.fileDatesTask = nil
            self.onLayoutChanged?()
        }
    }

    func fileDateOrder(_ ids: [String]) -> [String] {
        guard fileSort != .relevance, canSortFileResults else { return ids }
        let fileIDs = Set(results.filter { !$0.isApplication }.map(\.id))
        let sorted = ids.enumerated().filter { fileIDs.contains($0.element) }.sorted { a, b in
            let left = fileDates[a.element], right = fileDates[b.element]
            switch (left, right) {
            case let (l?, r?) where l != r: return fileSort == .createdNewest ? l > r : l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
        var iterator = sorted.makeIterator()
        // Apps and personal results retain their existing slots in All.
        return ids.map { fileIDs.contains($0) ? iterator.next()! : $0 }
    }
}
