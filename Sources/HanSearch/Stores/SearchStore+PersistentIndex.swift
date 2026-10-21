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
        panel.message = L.text("選擇要搜尋的文件與圖片資料夾，可一次多選。文字及 OCR 索引只保存在本機；iCloud 僅讀已下載檔案，不自動下載。")
        guard panel.runModal() == .OK else { return }
        do { try addDocumentRoots(panel.urls) }
        catch { indexNotice = "無法保存文件資料夾授權：" + error.localizedDescription }
    }
    func chooseCommonSearchFolders(_ selected: Set<CommonSearchFolder>) {
        guard !indexing, !catalogRefreshing, !selected.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = L.text("允許並建立索引")
        panel.message = L.text("可選擇使用者資料夾，一次授權下方勾選的常用位置；只索引勾選位置，不掃描 Library。也可以直接多選其他資料夾。")
            + "\n" + CommonSearchFolder.allCases.filter { selected.contains($0) }.map { L.text($0.title) }.joined(separator: "、")
        guard panel.runModal() == .OK else { return }
        do {
            try fileAccess.add(panel.urls)
            let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.resolvingSymlinksInPath()
            let roots = panel.urls.flatMap { url in
                url.standardizedFileURL.resolvingSymlinksInPath() == home ? CommonSearchFolder.allCases.filter { selected.contains($0) }.map(\.url) : [url]
            }.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !roots.isEmpty else { indexNotice = "尚未選擇可用的資料夾"; return }
            spotlightSupplement = true
            try addDocumentRoots(roots)
            addAuthorizedCatalogRoots(roots)
        } catch { indexNotice = "無法保存文件資料夾授權：" + error.localizedDescription }
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
        ocrWorkDecision = ocrResourcePolicy.decision()
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
                self.ocrWorkDecision = self.ocrResourcePolicy.decision()
                self.indexCurrentFile = progress.currentFile; self.indexCurrentPage = progress.currentPage
                self.indexTotalPages = progress.totalPages; self.indexRecognizing = progress.recognizing
                self.indexNotice = "Han 索引：已檢查 \(progress.examined) 份，擷取 \(progress.extracted) 份，沿用 \(progress.reused) 份"
            }
        }
        documentIndexTask = Task { [weak self] in
            do {
                let snapshot = try await Task.detached(priority: .background) {
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
            self.indexCurrentFile = ""; self.indexCurrentPage = 0; self.indexTotalPages = 0; self.indexRecognizing = false
            self.refreshSearchResults(); self.configureDocumentWatcher()
            if self.indexSnapshot.pendingOCR > 0 && self.ocrResourcePolicy.decision().canRun && !self.indexSnapshot.capped && !self.indexPaused && !cancellation.isCancelled {
                self.documentChangeTask?.cancel()
                self.documentChangeTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self, !self.indexPaused else { return }; self.rebuildIndex()
                }
            } else if self.documentChangePending && !self.indexPaused && self.autoRefreshEnabled { self.scheduleDocumentUpdate() }
        }
    }
    func applyIndexSnapshot(_ snapshot: DocumentIndexSnapshot) {
        indexSnapshot = snapshot; documentIssues = snapshot.issues; documentIndexCapped = snapshot.capped
        indexNotice = "Han 已收錄 \(snapshot.files) 份文件，\(snapshot.searchable) 份可搜尋內文，\(snapshot.unfinished) 份未完成"
            + (snapshot.capped ? "；空間或掃描範圍達限，尚有文件未收錄" : "")
        if snapshot.pendingOCR > 0 && ocrResourcePolicy.decision().canRun && !snapshot.capped && indexing && !indexPaused {
            sourceHealth[.contents, default: SourceHealth()].phase = .loading
        } else if snapshot.deferredOCR + snapshot.pendingOCR > 0 && !snapshot.capped && snapshot.unfinished == snapshot.deferredOCR + snapshot.pendingOCR {
            sourceHealth[.contents, default: SourceHealth()].phase = .waiting
            sourceHealth[.contents, default: SourceHealth()].partialUpdate = snapshot.updated
        } else if snapshot.capped || snapshot.unfinished > 0 {
            sourceHealth[.contents, default: SourceHealth()].phase = .incomplete
            sourceHealth[.contents, default: SourceHealth()].partialUpdate = snapshot.updated
        } else if let date = snapshot.updated { sourceHealth[.contents, default: SourceHealth()].succeeded(at: date) }
        refreshSearchResults()
    }
    /// No rescans while power/idle conditions remain unsuitable. The existing low-frequency
    /// refresh timer resumes committed OCR batches, independently of source auto-refresh.
    func reviewOCRResources() {
        ocrResourcePolicy.configure(allowBattery: ocrAllowBattery, idleOnly: ocrIdleOnly)
        ocrWorkDecision = ocrResourcePolicy.decision()
        guard ocrEnabled, !indexPaused, !indexing, !documentIndexRoots.isEmpty,
              !indexSnapshot.capped, indexSnapshot.deferredOCR + indexSnapshot.pendingOCR > 0,
              ocrWorkDecision.canRun else { return }
        rebuildIndex()
    }
    func pauseDocumentIndex() {
        indexPaused = true; documentChangePending = false
        documentChangeTask?.cancel(); documentWatcher.stop()
        documentIndexCancellation?.cancel()
        if !indexing { sourceHealth[.contents, default: SourceHealth()].phase = .stopped }
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
