import Foundation
import PDFKit

public struct SearchResponse: Sendable {
    public let items: [SearchItem]
    public let warning: String?
    public let truncated: Bool
    public init(items: [SearchItem], warning: String? = nil, truncated: Bool = false) {
        self.items = items; self.warning = warning; self.truncated = truncated
    }
}

public struct FolderIndex: Sendable {
    public let documents: [IndexedDocument]
    public let skippedText: Int
    public let capped: Bool
    public let issues: [DocumentReadIssue]
    public let examinedFiles: Int
    public let unsupportedFiles: Int
    public var extractedFiles: Int { documents.filter { !$0.text.isEmpty }.count }
}

public enum SearchService {
    public static let documentExtensions: Set<String> = ["txt", "md", "csv", "tsv", "srt", "json", "html", "htm", "doc", "docx", "rtf", "rtfd", "odt", "pdf", "ppt", "pptx", "pps", "ppsx", "pot", "potx", "pptm"]
    /// Query the existing system index, never recursively read the entire disk per keystroke.
    public static func documentQuery(_ query: String) -> String {
        let clean = String(query.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? Character(" ") : Character($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        let variants = ChineseSearch.indexedVariants(clean)
        return variants.count == 1 ? clean : variants.map { "(" + $0 + ")" }.joined(separator: " OR ")
    }
    public static func searchDocumentContents(query: String, folder: URL? = nil, cancellation: ProcessCancellation? = nil) -> SearchResponse {
        let interpreted = documentQuery(query)
        guard !interpreted.isEmpty else { return SearchResponse(items: []) }
        do {
            // The native user-query parser handles Chinese index segmentation. A raw
            // kMDItemTextContent comparison can silently miss an indexed Chinese phrase.
            var args = ["-0", "-interpret"]
            if let folder { args += ["-onlyin", folder.path] }
            let data = try ProcessRunner.run("/usr/bin/mdfind", args + [interpreted], cancellation: cancellation, outputLimit: 16_000_000)
            let paths = data.split(separator: 0)
            let items = paths.compactMap { bytes -> SearchItem? in
                guard let path = String(data: Data(bytes), encoding: .utf8) else { return nil }
                let url = URL(fileURLWithPath: path, isDirectory: false)
                guard documentExtensions.contains(url.pathExtension.lowercased()) else { return nil }
                return SearchItem(url: url, source: "文件・系統索引")
            }
            return SearchResponse(items: Array(items.prefix(2000)), truncated: items.count > 2000)
        } catch is CancellationError { return SearchResponse(items: []) }
        catch { return SearchResponse(items: [], warning: error.localizedDescription) }
    }
    public static func search(query: String, mode: SearchMode, folder: URL? = nil, cancellation: ProcessCancellation? = nil) -> SearchResponse {
        if mode == .contents { return searchDocumentContents(query: query, folder: folder, cancellation: cancellation) }
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

    private static let applicationCatalog = ApplicationCatalog.scan()
    public static let installedApplications = applicationCatalog.map(\.searchItem)
    public static func searchApplications(query: String, aliasTargets: Set<String> = []) -> [SearchItem] {
        let terms = ChineseSearch.terms(ChineseSearch.normalized(query))
        guard !terms.isEmpty else { return [] }
        return applicationCatalog.filter { $0.matches(terms: terms) || aliasTargets.contains("app:" + $0.preferenceID) }.map(\.searchItem)
    }

    public static func index(folder: URL) -> FolderIndex {
        var documents: [IndexedDocument] = []
        var extractedBytes = 0
        var issues: [DocumentReadIssue] = [], examined = 0, unsupported = 0
        let supported = documentExtensions
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, _ in
            issues.append(DocumentReadIssue(url: url, reason: .readFailed)); return true
        }) else {
            return FolderIndex(documents: [], skippedText: 1, capped: false, issues: [DocumentReadIssue(url: folder, reason: .readFailed)], examinedFiles: 0, unsupportedFiles: 0)
        }
        var capped = false
        for case let url as URL in enumerator {
            if Task<Never, Never>.isCancelled { break }
            if documents.count >= 10000 { capped = true; break }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]), values.isRegularFile == true else { continue }
            examined += 1
            let ext = url.pathExtension.lowercased()
            guard supported.contains(ext) else { unsupported += 1; continue }
            var body = ""
            if supported.contains(ext) {
                if (values.fileSize ?? 0) > 20_000_000 {
                    issues.append(DocumentReadIssue(url: url, reason: .tooLarge))
                } else if values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded {
                    issues.append(DocumentReadIssue(url: url, reason: .cloudOnly))
                } else {
                    do {
                        let extracted = try extractText(url)
                        if extractedBytes + extracted.utf8.count > 32_000_000 { issues.append(DocumentReadIssue(url: url, reason: .textBudget)) }
                        else { body = extracted; extractedBytes += extracted.utf8.count }
                    }
                    catch { issues.append(DocumentReadIssue(url: url, reason: error as? DocumentReadReason ?? .readFailed)) }
                }
            }
            documents.append(IndexedDocument(url: url, text: body))
        }
        return FolderIndex(documents: documents, skippedText: issues.count, capped: capped, issues: issues, examinedFiles: examined, unsupportedFiles: unsupported)
    }

    public static func extractText(_ url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ["pptx", "ppsx", "potx", "pptm"].contains(ext) { return try PresentationText.extract(url) }
        if ["ppt", "pps", "pot"].contains(ext) {
            let data = try ProcessRunner.run("/usr/bin/mdls", ["-raw", "-name", "kMDItemTextContent", url.path], timeout: 10, outputLimit: 8_000_000)
            guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.trimmingCharacters(in: .whitespacesAndNewlines) != "(null)" else {
                throw DocumentReadReason.legacyNeedsSystemIndex
            }
            return text
        }
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else { throw DocumentReadReason.readFailed }
            guard !doc.isLocked else { throw DocumentReadReason.locked }
            guard let text = doc.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DocumentReadReason.noText }
            return text
        }
        if ["doc", "docx", "rtf", "rtfd", "odt", "html", "htm"].contains(ext) {
            let data = try ProcessRunner.run("/usr/bin/textutil", ["-convert", "txt", "-encoding", "UTF-8", "-stdout", url.path], timeout: 10, outputLimit: 32_000_000)
            guard let text = String(data: data, encoding: .utf8) else { throw ProcessFailure.failed("文件文字編碼無法讀取。") }
            return text
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static func merge(_ items: [SearchItem], query: String, limit: Int = 200) -> [SearchItem] {
        var byPath: [String: SearchItem] = [:]
        for item in items {
            // Keep the informative local preview when Spotlight returns the same file.
            if byPath[item.id] == nil || !item.excerpt.isEmpty || (item.applicationIdentifier != nil && byPath[item.id]?.applicationIdentifier == nil) { byPath[item.id] = item }
        }
        let needle = ChineseSearch.normalized(query)
        func score(_ item: SearchItem) -> Int {
            let name = ChineseSearch.normalized(item.name)
            let compactName = item.isApplication ? ChineseSearch.applicationKey(item.name) : name
            let compactNeedle = item.isApplication ? ChineseSearch.applicationKey(query) : needle
            let alias = item.isApplication && ApplicationAliases.matches(query, aliases: ApplicationAliases.aliases(name: item.name, bundleID: item.applicationIdentifier))
            return (compactName == compactNeedle ? 100 : 0) + (compactName.hasPrefix(compactNeedle) ? 30 : 0) + (compactName.contains(compactNeedle) ? 10 : 0) + (alias ? 80 : 0) + (item.isApplication ? 5 : 0)
        }
        return Array(byPath.values.sorted { a, b in
            let x = score(a), y = score(b)
            return x == y ? a.url.path < b.url.path : x > y
        }.prefix(limit))
    }
}
