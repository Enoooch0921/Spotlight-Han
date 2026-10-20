import Foundation
import AppKit
import HanSearchCore

extension SearchStore {
    func loadPersistentDocumentIndex() async {
        guard !documentIndexRoots.isEmpty else {
            if !unavailableDocumentRoots.isEmpty { indexNotice = "文件資料夾授權無法恢復，請重新選擇；未顯示快取內文" }
            return
        }
        let index = documentIndex, roots = documentIndexRoots
        do {
            let snapshot = try await Task.detached(priority: .utility) { try index.statistics(roots: roots) }.value
            applyIndexSnapshot(snapshot)
            if autoRefreshEnabled { rebuildIndex() }
            configureDocumentWatcher()
        } catch { indexNotice = error.localizedDescription; sourceHealth[.contents] = SourceHealth(phase: .failed, lastAttempt: Date()) }
    }
    func chooseFolder() {
        guard !indexing else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.prompt = L.text("建立 Han 索引")
        panel.message = L.text("選擇要保存在本機搜尋索引的文件資料夾。只讀取支援的文字文件，不複製原始檔；可一次選擇多個資料夾。")
        guard panel.runModal() == .OK else { return }
        do { try addDocumentRoots(panel.urls) }
        catch { indexNotice = "無法保存文件資料夾授權：" + error.localizedDescription }
    }
    func addDocumentRoots(_ roots: [URL]) throws {
        guard !indexing else { return }
        try fileAccess.add(roots)
        let recovered = fileAccess.restoreIndexRoots(unavailableDocumentRoots.map(\.path))
        unavailableDocumentRoots = recovered.unavailable
        for root in recovered.available + roots {
            let root = root.standardizedFileURL.resolvingSymlinksInPath()
            if !documentRoots.contains(where: { root.path == $0.path || root.path.hasPrefix($0.path + "/") }) {
                documentRoots.removeAll { $0.path.hasPrefix(root.path + "/") }; documentRoots.append(root)
            }
        }
        folder = documentRoots.first
        saveDocumentRoots(); rebuildIndex(); configureDocumentWatcher()
    }
    func saveDocumentRoots() {
        taskPreferences.set(Array(Set((documentRoots + unavailableDocumentRoots).map(\.path))).sorted(), forKey: "documentIndexRoots.v1")
    }
    func rebuildIndex() {
        guard !indexing, !documentIndexRoots.isEmpty else { return }
        indexPaused = false; indexing = true; documentChangePending = false
        let index = documentIndex, roots = documentIndexRoots
        let cancellation = ProcessCancellation(), token = UUID()
        documentIndexCancellation = cancellation; documentIndexGeneration = token
        sourceHealth[.contents, default: SourceHealth()].phase = .loading
        sourceHealth[.contents, default: SourceHealth()].lastAttempt = Date()
        indexNotice = "正在更新 Han 文件索引；既有結果仍可搜尋…"
        let update: @Sendable (DocumentIndexSnapshot) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, self.documentIndexGeneration == token, self.indexing else { return }
                self.indexNotice = "Han 索引：已檢查 \(progress.examined) 份，擷取 \(progress.extracted) 份，沿用 \(progress.reused) 份"
            }
        }
        documentIndexTask = Task { [weak self] in
            do {
                let snapshot = try await Task.detached(priority: .utility) {
                    try index.synchronize(roots: roots, cancellation: cancellation, progress: update)
                }.value
                guard let self, self.documentIndexGeneration == token else { return }
                self.applyIndexSnapshot(snapshot)
            } catch {
                guard let self, self.documentIndexGeneration == token else { return }
                if cancellation.isCancelled {
                    self.indexNotice = "Han 索引已暫停；已儲存的文件仍可搜尋"
                    self.sourceHealth[.contents, default: SourceHealth()].phase = .stopped
                } else {
                    self.indexNotice = error.localizedDescription
                    self.sourceHealth[.contents, default: SourceHealth()].phase = .failed
                }
            }
            guard let self, self.documentIndexGeneration == token else { return }
            self.indexing = false; self.documentIndexCancellation = nil; self.documentIndexTask = nil
            self.refreshSearchResults(); self.configureDocumentWatcher()
            if self.documentChangePending && !self.indexPaused && self.autoRefreshEnabled { self.scheduleDocumentUpdate() }
        }
    }
    func applyIndexSnapshot(_ snapshot: DocumentIndexSnapshot) {
        indexSnapshot = snapshot; documentIssues = snapshot.issues; documentIndexCapped = snapshot.capped
        indexNotice = "Han 已收錄 \(snapshot.files) 份文件，\(snapshot.searchable) 份可搜尋內文，\(snapshot.unfinished) 份未完成"
            + (snapshot.capped ? "；空間或掃描範圍達限，尚有文件未收錄" : "")
        if snapshot.capped || snapshot.unfinished > 0 {
            sourceHealth[.contents, default: SourceHealth()].phase = .incomplete
            sourceHealth[.contents, default: SourceHealth()].partialUpdate = snapshot.updated
        } else if let date = snapshot.updated { sourceHealth[.contents, default: SourceHealth()].succeeded(at: date) }
        refreshSearchResults()
    }
    func pauseDocumentIndex() {
        indexPaused = true; documentChangePending = false
        documentChangeTask?.cancel(); documentWatcher.stop()
        documentIndexCancellation?.cancel()
    }
    func configureDocumentWatcher() {
        guard autoRefreshEnabled, !indexPaused, !documentIndexRoots.isEmpty else { documentWatcher.stop(); return }
        documentWatcher.start(roots: documentIndexRoots, excluded: documentIndexURL.deletingLastPathComponent()) { [weak self] in
            Task { @MainActor in self?.scheduleDocumentUpdate() }
        }
    }
    func scheduleDocumentUpdate() {
        guard autoRefreshEnabled, !indexPaused else { return }
        sourceHealth[.contents]?.markChanged(); documentChangePending = true
        guard !indexing else { return }
        documentChangeTask?.cancel()
        documentChangeTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.autoRefreshEnabled, !self.indexPaused else { return }
            self.rebuildIndex()
        }
    }
    func removeDocumentRoot(_ url: URL) {
        guard !indexing else { return }
        documentRoots.removeAll { $0.path == url.path }; unavailableDocumentRoots.removeAll { $0.path == url.path }
        folder = documentRoots.first; saveDocumentRoots(); pruneDocumentIndex()
    }
    func clearDocumentScopes() {
        guard !indexing else { return }
        documentRoots = []; unavailableDocumentRoots = []; folder = nil; saveDocumentRoots(); pruneDocumentIndex()
    }
    func resetScope() { clearDocumentScopes() }
    func pruneDocumentIndex() {
        documentWatcher.stop(); documentChangeTask?.cancel(); documentChangePending = false
        indexing = true
        let roots = documentRoots + unavailableDocumentRoots, index = documentIndex
        resetDocumentVerification(); cachedGlobalQuery = nil; cachedGlobalContents = []; search()
        documentIndexTask = Task {
            do {
                try await Task.detached(priority: .utility) { try index.retain(roots: roots) }.value
                let snapshot = try await Task.detached(priority: .utility) { try index.statistics(roots: roots) }.value
                applyIndexSnapshot(snapshot)
                if roots.isEmpty { sourceHealth[.contents] = nil; documentIssues = []; indexNotice = "已清除 Han 文件索引" }
            } catch { indexNotice = error.localizedDescription; sourceHealth[.contents, default: SourceHealth()].phase = .failed }
            indexing = false; documentIndexTask = nil; configureDocumentWatcher(); refreshSearchResults()
        }
    }
    func clearAndRebuildDocumentIndex() {
        guard !indexing else { return }
        documentWatcher.stop(); documentChangeTask?.cancel(); indexing = true
        let index = documentIndex
        documentIndexTask = Task {
            do {
                try await Task.detached(priority: .utility) { try index.retain(roots: []) }.value
                indexSnapshot = DocumentIndexSnapshot(); documentIssues = []
                indexing = false; rebuildIndex()
            } catch { indexing = false; indexNotice = error.localizedDescription }
        }
    }
    func revealDocumentIndex() {
        NSWorkspace.shared.selectFile(documentIndexURL.path, inFileViewerRootedAtPath: documentIndexURL.deletingLastPathComponent().path)
    }
}
