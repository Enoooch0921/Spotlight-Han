import Foundation
import HanSearchCore

extension ChineseSearchTests {
    func testFileWorkflows() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9))!
        let filter = FileQueryFilter("上週修改的 PDF 報價單", now: now, calendar: cal)
        precondition(filter.chips.count == 2 && filter.extensions == ["pdf"] && filter.text == "報價單")
        precondition(filter.removing(.date) == "PDF 報價單" && filter.removing(.type) == "上週修改的 報價單")
        precondition(FileQueryFilter("上周修改的 PDF 报价单").text == "报价单")
        precondition(!FileQueryFilter("上週報告").active && FileQueryFilter("上週報告").suggestedWeek != nil)
        precondition(!FileQueryFilter("PDF報價單.pdf").active && !FileQueryFilter("Logic Pro").active)
        for input in ["下載資料夾裡的 DL32", "下载文件夹里的 DL32"] {
            let scope = FileQueryFilter(input)
            precondition(scope.folder == .downloads && scope.text == "DL32")
            precondition(scope.accepts(CommonSearchFolder.downloads.url.appendingPathComponent("DL32.pdf")))
            precondition(!scope.accepts(CommonSearchFolder.desktop.url.appendingPathComponent("DL32.pdf")))
        }
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let start = filter.interval!.start, end = filter.interval!.end
        precondition(cal.component(.weekday, from: start) == 2 && cal.component(.day, from: start) == 16)
        let pdf = folder.appendingPathComponent("报价单.pdf")
        try Data("example".utf8).write(to: pdf)
        try FileManager.default.setAttributes([.modificationDate: end], ofItemAtPath: pdf.path)
        precondition(!filter.accepts(pdf))
        try FileManager.default.setAttributes([.modificationDate: start], ofItemAtPath: pdf.path)
        let entries = [CatalogEntry(url: pdf), CatalogEntry(url: folder.appendingPathComponent("報價單.txt"))]
        precondition(FileCatalog.search(entries, query: filter.text, mode: .all, filter: filter).map(\.url) == [pdf])
        let file = folder.appendingPathComponent("z報價單.txt")
        try "保固".write(to: file, atomically: true, encoding: .utf8)
        let index = PersistentDocumentIndex(databaseURL: root.appendingPathComponent("index/docs.sqlite"))
        let before = try index.status(of: file, roots: [folder])
        precondition(before == .missing)
        _ = try index.synchronize(roots: [folder])
        let recorded = try index.status(of: file, roots: [folder])
        guard case .recorded(true, nil, _, false) = recorded else { preconditionFailure("Expected indexed text") }
        let outside = try index.status(of: file, roots: [])
        let excluded = try index.status(of: folder.appendingPathComponent("Caches/test.txt"), roots: [folder])
        let unsupported = try index.status(of: folder.appendingPathComponent("test.mp4"), roots: [folder])
        precondition(outside == .outside && excluded == .excluded && unsupported == .unsupported)
        let onlyPDF = FileQueryFilter("PDF 報價單")
        let filtered = try index.search(query: onlyPDF.text, roots: [folder], limit: 1, filter: onlyPDF)
        precondition(filtered.items.map(\.url) == [pdf])
        let dated = FileQueryFilter("上週修改的 PDF", now: now, calendar: cal)
        let browsed = try index.search(query: dated.text, roots: [folder], filter: dated)
        precondition(browsed.items.map(\.url) == [pdf])
        try "已更新".write(to: file, atomically: true, encoding: .utf8)
        guard case .recorded(_, _, _, true) = try index.status(of: file, roots: [folder]) else { preconditionFailure("Expected changed file") }

        var history = SearchHabitHistory(salt: "fixture")
        history.setLowered(true, query: "報價", fileID: file.path)
        let bytes = try JSONEncoder().encode(history)
        precondition(!String(decoding: bytes, as: UTF8.self).contains(file.path))
        var loaded = try JSONDecoder().decode(SearchHabitHistory.self, from: bytes)
        precondition(loaded.loweredFiles(query: "报价", ids: [file.path, pdf.path]) == [file.path])
        precondition(loaded.loweredFiles(query: "報價單", ids: [file.path]).isEmpty)
        loaded.setLowered(false, query: "報價", fileID: file.path)
        precondition(!loaded.hasCorrections)
        print("PASS: file filters, calendar boundaries, exact folder scope, script variants, filter chips, index diagnosis, metadata-only queries and reversible private ranking corrections")
    }
}
