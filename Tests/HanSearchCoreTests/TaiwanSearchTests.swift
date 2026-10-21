import Foundation
import HanSearchCore

extension ChineseSearchTests {
    func testTaiwanSearchSupplements() throws {
        let calculator = InstalledApplication(url: URL(fileURLWithPath: "/fixture/Calculator.app"), name: "Calculator", bundleID: "com.apple.calculator")
        for input in ["rnr", "RNR", "ru4nj04ru", "ru4nj04ru ", "ru4nj04ru ".trimmingCharacters(in: .whitespaces)] {
            precondition(calculator.matches(input), "Expected Calculator for \(input)")
            precondition(calculator.supplement(for: input)?.kind == .zhuyinKeyboard)
        }
        for input in ["rn", "ru", "rnrn", "rnr!", "dl32", "DL32", "m32", "dl 32", "logicpro", "fcp", "wifi", "https://example.com", "ru44nj04ru"] {
            precondition(!calculator.matches(input), "Unrelated input must not guess Calculator: \(input)")
        }
        for input in ["計算機", "计算机", "jsj", "ㄐㄙㄐ", "Calculator"] {
            precondition(calculator.matches(input) && calculator.supplement(for: input) == nil)
        }
        let encoded = try JSONEncoder().encode(PhoneticSearch("計算機"))
        let decoded = try JSONDecoder().decode(PhoneticSearch.self, from: encoded)
        precondition(ZhuyinKeyboard.Query("rnr")!.matches(decoded), "Existing phonetic cache schema remains compatible")
        let exactApp = InstalledApplication(url: URL(fileURLWithPath: "/fixture/rnr.app"), name: "rnr")
        let sorted = SearchService.merge([calculator.searchItem(query: "rnr"), exactApp.searchItem], query: "rnr")
        precondition(sorted.map(\.id) == [exactApp.id, calculator.id])
        let filename = CatalogEntry(url: URL(fileURLWithPath: "/fixture/計算機指南.pdf"))
        precondition(FileCatalog.search([filename], query: "rnr", mode: .names).isEmpty)
        let notes = PersonalRecord(id: "note:calc", title: "計算機", subtitle: "", text: "計算機", symbol: "note", mode: .notes, action: .details("fixture"))
        precondition(notes.result(query: "rnr", mode: .all) == nil)

        for pair in [("隨身碟", "U盤"), ("列印", "打印"), ("印表機", "打印機"), ("滑鼠", "鼠標"), ("軟體", "軟件"), ("硬體", "硬件")] {
            for (query, target) in [pair, (pair.1, pair.0)] {
                let alternatives = TaiwanVocabulary.alternatives(for: query)
                precondition(alternatives.contains { ChineseSearch.matches(target, query: $0.query) }, "Bidirectional wording \(query) → \(target)")
                let doc = IndexedDocument(url: URL(fileURLWithPath: "/fixture/unrelated.txt"), text: "開頭\n" + String(repeating: "一般內容", count: 100) + target + "的操作教學。")
                let hit = doc.match(query: query, mode: .contents)!
                precondition(hit.supplement?.kind == .taiwanVocabulary && hit.excerpt.contains(target))
                precondition(!SearchHighlight.ranges(in: hit.excerpt, query: hit.supplement!.query).isEmpty)
                let record = PersonalRecord(id: "note:wording", title: "操作教學", subtitle: "", text: target, symbol: "note", mode: .notes, action: .details("original-content"))
                let quick = record.result(query: query, mode: .all)!
                precondition(quick.id == "quick:note:wording" && quick.action == .details("original-content") && quick.supplement != nil)
            }
        }
        precondition(TaiwanVocabulary.alternatives(for: "打印機").map(\.query) == [ChineseSearch.normalized("印表機")], "Do not also expand the shorter 打印 phrase")
        precondition(TaiwanVocabulary.alternatives(for: "CPU盤點").isEmpty, "U盤 must not match inside CPU盤點")
        for query in ["dl32", "如果只能用", "文件", "檔案", "影片", "視頻", "a+b", "U", "盤"] { precondition(TaiwanVocabulary.alternatives(for: query).isEmpty) }
        let many = TaiwanVocabulary.alternatives(for: "滑鼠 列印 軟體 硬體 隨身碟")
        precondition(many.count <= 7 && Set(many.map(\.query)).count == many.count)
        precondition(IndexedDocument(url: URL(fileURLWithPath: filename.path), text: "打印說明").match(query: "列印 退貨", mode: .all) == nil, "Expansion cannot drop other query terms")

        let originalFile = CatalogEntry(url: URL(fileURLWithPath: "/fixture/z-列印.txt"))
        let relatedFile = CatalogEntry(url: URL(fileURLWithPath: "/fixture/a-打印.txt"))
        let unrelated = CatalogEntry(url: URL(fileURLWithPath: "/fixture/列隊.txt"))
        let files = FileCatalog.search([relatedFile, unrelated, originalFile], query: "列印", mode: .names)
        precondition(files.map(\.id) == [originalFile.path, relatedFile.path] && files.last?.supplement?.kind == .taiwanVocabulary)
        precondition(FileCatalog.search([relatedFile], query: "列印", mode: .names, folder: URL(fileURLWithPath: "/elsewhere")).isEmpty)
        let direct = SearchItem(url: URL(fileURLWithPath: relatedFile.path), source: "direct")
        let related = SearchItem(url: URL(fileURLWithPath: relatedFile.path), source: "related", excerpt: "打印內容", supplement: files.last!.supplement)
        for candidates in [[direct, related], [related, direct]] {
            precondition(SearchService.merge(candidates, query: "列印").first?.supplement == nil, "Deduplication never converts a primary match into a supplement")
        }
        let unverifiable = SearchItem(url: related.url, source: "文件・系統索引")
        for candidates in [[unverifiable, related], [related, unverifiable]] {
            precondition(SearchService.merge(candidates, query: "列印").first?.supplement != nil, "Unverified system candidates must not replace verified local excerpts")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HanTaiwanSearch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("z-direct.txt"), alternative = root.appendingPathComponent("a-related.txt")
        try "列印說明".write(to: original, atomically: true, encoding: .utf8)
        try "打印說明".write(to: alternative, atomically: true, encoding: .utf8)
        try "打字練習，印章準備；分散字元不能算命中。".write(to: root.appendingPathComponent("false-grams.txt"), atomically: true, encoding: .utf8)
        let index = PersistentDocumentIndex(databaseURL: root.appendingPathComponent("Index/test.sqlite"))
        _ = try index.synchronize(roots: [root])
        let hit = try index.search(query: "列印", roots: [root], mode: .contents)
        precondition(hit.items.map(\.url.lastPathComponent) == [original.lastPathComponent, alternative.lastPathComponent])
        precondition(hit.items.first?.supplement == nil && hit.items.last?.supplement?.kind == .taiwanVocabulary)
        precondition(hit.items.last?.excerpt == "打印說明")
        let limited = try index.search(query: "列印", roots: [root], mode: .contents, limit: 1)
        let extraTerm = try index.search(query: "列印 退貨", roots: [root])
        let wrongScope = try index.search(query: "列印", roots: [root.appendingPathComponent("elsewhere")])
        let keyboardBody = try index.search(query: "rnr", roots: [root])
        precondition(limited.items.first?.supplement == nil)
        precondition(extraTerm.items.isEmpty && wrongScope.items.isEmpty && keyboardBody.items.isEmpty)
        print("PASS: conservative Zhuyin-key App recovery, exact-first deduplication, six bounded wording pairs, original excerpts/highlights, term/scope/model guards and existing persistent index queries")
    }
}
