import Foundation
import PDFKit

public struct SearchResponse: Sendable {
    public let items: [SearchItem]
    public let warning: String?
    public let truncated: Bool
}

public struct FolderIndex: Sendable {
    public let documents: [IndexedDocument]
    public let skippedText: Int
    public let capped: Bool
}

public enum SearchService {
    public static func search(query: String, mode: SearchMode, folder: URL? = nil, cancellation: ProcessCancellation? = nil) -> SearchResponse {
        var items: [SearchItem] = []
        var warning: String?
        var truncated = false
        do {
            var args = ["-0"]
            if let folder { args += ["-onlyin", folder.path] }
            args.append(ChineseSearch.predicate(query, mode: mode))
            let data = try ProcessRunner.run("/usr/bin/mdfind", args, cancellation: cancellation)
            let paths = data.split(separator: 0)
            truncated = paths.count > 2000
            items = paths.prefix(2000).compactMap { bytes in
                guard let path = String(data: Data(bytes), encoding: .utf8),
                      FileManager.default.fileExists(atPath: path) else { return nil }
                return SearchItem(url: URL(fileURLWithPath: path), source: "Spotlight")
            }
        } catch { warning = error.localizedDescription }

        // App names are also checked locally, so this does not depend solely on indexing.
        if folder == nil && mode != .contents {
            items += searchApplications(query: query)
        }
        return SearchResponse(items: items, warning: warning, truncated: truncated)
    }

    public static let installedApplications: [SearchItem] = loadApplications()
    private static let foldedApplications = installedApplications.map { ($0, ChineseSearch.normalized($0.name + " " + $0.url.lastPathComponent)) }

    public static func searchApplications(query: String) -> [SearchItem] {
        let terms = ChineseSearch.terms(ChineseSearch.normalized(query))
        guard !terms.isEmpty else { return [] }
        return foldedApplications.filter { entry in terms.allSatisfy { entry.1.contains($0) } }.map { $0.0 }
    }

    private static func loadApplications() -> [SearchItem] {
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        var items: [SearchItem] = []
        for path in roots {
            guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                let bundle = Bundle(url: url)
                let name = (bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
                    ?? (bundle?.localizedInfoDictionary?["CFBundleName"] as? String)
                    ?? (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                items.append(SearchItem(url: url, name: name, source: "App・繁簡比對"))
            }
        }
        return items
    }

    public static func index(folder: URL) -> FolderIndex {
        var documents: [IndexedDocument] = []
        var skipped = 0
        var extractedBytes = 0
        let supported = Set(["txt", "md", "csv", "tsv", "srt", "json", "html", "htm", "doc", "docx", "rtf", "rtfd", "odt", "pdf"])
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return FolderIndex(documents: [], skippedText: 0, capped: false)
        }
        var capped = false
        for case let url as URL in enumerator {
            if Task<Never, Never>.isCancelled { break }
            if documents.count >= 10000 { capped = true; break }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), values.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            var body = ""
            if supported.contains(ext) {
                if (values.fileSize ?? 0) > 20_000_000 || (values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded) {
                    skipped += 1
                } else {
                    do {
                        let extracted = try extractText(url)
                        if extractedBytes + extracted.utf8.count > 32_000_000 { skipped += 1 }
                        else { body = extracted; extractedBytes += extracted.utf8.count }
                    }
                    catch { skipped += 1 }
                }
            }
            documents.append(IndexedDocument(url: url, text: body))
        }
        return FolderIndex(documents: documents, skippedText: skipped, capped: capped)
    }

    public static func extractText(_ url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url), let text = doc.string, !text.isEmpty else {
                throw ProcessFailure.failed("PDF 沒有可擷取的文字（可能需要 OCR）。")
            }
            return text
        }
        if ["doc", "docx", "rtf", "rtfd", "odt", "html", "htm"].contains(ext) {
            let data = try ProcessRunner.run("/usr/bin/textutil", ["-convert", "txt", "-encoding", "UTF-8", "-stdout", url.path], timeout: 10)
            guard let text = String(data: data, encoding: .utf8) else { throw ProcessFailure.failed("文件文字編碼無法讀取。") }
            return text
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static func merge(_ items: [SearchItem], query: String, limit: Int = 200) -> [SearchItem] {
        var byPath: [String: SearchItem] = [:]
        for item in items {
            // Keep the informative local preview when Spotlight returns the same file.
            if byPath[item.id] == nil || !item.excerpt.isEmpty { byPath[item.id] = item }
        }
        let needle = ChineseSearch.normalized(query)
        func score(_ item: SearchItem) -> Int {
            let name = ChineseSearch.normalized(item.name)
            return (name == needle ? 100 : 0) + (name.hasPrefix(needle) ? 30 : 0) + (name.contains(needle) ? 10 : 0) + (item.isApplication ? 5 : 0)
        }
        return Array(byPath.values.sorted { a, b in
            let x = score(a), y = score(b)
            return x == y ? a.url.path < b.url.path : x > y
        }.prefix(limit))
    }
}
