import SwiftUI
import AppKit
import HanSearchCore

struct FileInspectionView: View {
    @ObservedObject var store: SearchStore
    let url: URL
    @State private var status: IndexedFileStatus?
    @State private var nameFound: Bool?
    @State private var error = ""
    private var nameCovered: Bool { store.documentIndex.contains(url.resolvingSymlinksInPath().path, roots: store.catalogRoots) }
    private var needsContentRoot: Bool { status == .outside }
    private var busy: Bool { store.indexing || store.catalogRefreshing }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L.text("檔案搜尋診斷"), systemImage: "doc.text.magnifyingglass").font(.headline)
            Text(url.lastPathComponent).font(.title3.weight(.semibold)).lineLimit(2)
            Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Divider()
            LabeledContent(L.text("檔名清單")) {
                if let nameFound {
                    Text(L.text(nameFound ? "已收錄" : nameCovered ? "目前清單沒有這個檔名" : "資料夾未加入檔名搜尋"))
                } else { Text(L.text("正在檢查…")) }
            }
            LabeledContent(L.text("文件內文")) { Text(contentStatus).multilineTextAlignment(.trailing) }
            if case let .recorded(_, reason, pages, changed) = status {
                if pages > 0 { Text(L.format("已處理 %@ 頁", String(pages))).font(.caption) }
                if let reason { Text(L.text(reason.recoverySuggestion)).font(.callout) }
                if changed { Label(L.text("檔案在收錄後已變更"), systemImage: "clock").foregroundStyle(.orange) }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.orange) }
            Spacer(minLength: 0)
            HStack {
                Button(L.text("返回搜尋")) { store.escapeLauncherLayer() }
                Spacer()
                if needsContentRoot || !nameCovered {
                    Button(L.text("加入所在資料夾…")) { addParent() }.disabled(busy || status == nil)
                }
                if nameCovered || store.documentIndex.contains(url.resolvingSymlinksInPath().path, roots: store.documentIndexRoots) {
                    Button(L.text(busy ? "正在更新…" : "更新已選索引")) {
                        if nameCovered { store.refreshCatalog() }
                        if store.documentIndex.contains(url.resolvingSymlinksInPath().path, roots: store.documentIndexRoots) { store.rebuildIndex() }
                    }.disabled(busy)
                }
            }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: "\(url.path)|\(store.indexing)|\(store.catalogRefreshing)|\(store.catalogRoots)|\(store.documentIndexRoots)") {
            let index = store.documentIndex, roots = store.documentIndexRoots, entries = store.entries
            status = nil; nameFound = nil; error = ""
            let read = Task.detached(priority: .utility) {
                let path = url.resolvingSymlinksInPath().path
                let found = entries.contains { $0.path == path }
                return (found, Result { try index.status(of: url, roots: roots) })
            }
            let result = await read.value
            guard !Task.isCancelled else { return }
            nameFound = result.0
            do { status = try result.1.get() } catch { self.error = error.localizedDescription }
        }
    }
    private var contentStatus: String {
        switch status {
        case .outside: return L.text("資料夾未加入內文搜尋")
        case .unsupported: return L.text("此格式不支援內文索引")
        case .excluded: return L.text("此路徑依索引規則排除")
        case .missing: return L.text("範圍內，尚無此檔的索引紀錄")
        case let .recorded(hasText, reason, _, _):
            return [hasText ? L.text("已有可搜尋內文") : L.text("尚無可搜尋內文"), reason.map { L.text($0.title) }].compactMap { $0 }.joined(separator: " · ")
        case nil: return L.text(error.isEmpty ? "正在檢查…" : "無法讀取索引")
        }
    }
    private func addParent() {
        let parent = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let picker = NSOpenPanel()
        picker.directoryURL = parent; picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.prompt = L.text("加入所在資料夾")
        guard picker.runModal() == .OK, let chosen = picker.url else { return }
        guard chosen.standardizedFileURL.resolvingSymlinksInPath().path == parent.path else {
            error = L.text("請選取這個檔案所在的資料夾"); return
        }
        do {
            try store.fileAccess.add([chosen])
            if needsContentRoot { try store.addDocumentRoots([chosen]) }
            if !nameCovered { store.addAuthorizedCatalogRoots([chosen]) }
        } catch { self.error = error.localizedDescription }
    }
}

struct FileFilterBar: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        let filter = store.parsedFileQuery
        if filter.active || filter.suggestedWeek != nil {
            HStack {
                ForEach(filter.chips, id: \.kind) { chip in
                    Button { store.query = filter.removing(chip.kind) } label: {
                        Label(chip.phrase, systemImage: "xmark.circle.fill")
                    }.help(L.text("移除條件"))
                }
                if let week = filter.suggestedWeek {
                    Button(L.text("限定上週修改")) {
                        store.query = (filter.chips.map(\.phrase) + [week + "修改的", String(filter.text.dropFirst(week.count))]).joined(separator: " ")
                    }
                }
                Spacer()
            }.buttonStyle(.bordered).controlSize(.small).padding(.horizontal, 16).padding(.vertical, 6)
        }
    }
}

/// A row marker lets the panel begin a native drag without taking clicks,
/// contextual menus or accessibility focus away from the SwiftUI result.
struct FileDragRegion: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> Region { Region() }
    func updateNSView(_ view: Region, context: Context) { view.url = url }

    final class Region: NSView, NSDraggingSource {
        static let visible = NSHashTable<Region>.weakObjects()
        var url: URL?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { Self.visible.remove(self) } else { Self.visible.add(self) }
        }
        static func at(_ point: NSPoint, in window: NSWindow) -> Region? {
            visible.allObjects.first { region in
                region.window === window && !region.isHiddenOrHasHiddenAncestor &&
                    region.visibleRect.contains(region.convert(point, from: nil))
            }
        }
        func beginFileDrag(_ url: URL, with event: NSEvent) {
            let item = FileResultActions.draggingItem(for: url)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let point = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(origin: point, size: NSSize(width: 40, height: 40)), contents: icon)
            beginDraggingSession(with: [item], event: event, source: self)
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : []
        }
    }
}
