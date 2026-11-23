import AppKit
import HanSearchCore
import UniformTypeIdentifiers

enum SearchResultDrag {
    case url(URL)
    case text(title: String, value: String, symbol: String, app: SystemSourceApp?)

    init?(_ result: QuickResult) {
        let value: String
        switch result.action {
        case .note:
            // Notes exposes a record, not a filesystem URL. Use the indexed
            // plaintext, never the shortened, query-dependent result subtitle.
            value = result.noteText.flatMap { $0.isEmpty ? nil : $0 } ?? result.title
        case .copy(let text): value = text
        case .details(let text):
            guard ["quick:contact:", "quick:event:", "quick:reminder:", "quick:dictionary"].contains(where: result.id.hasPrefix) else { return nil }
            value = text
        case .open(let url):
            self = .url(url)
            return
        case .createTask, .prepareTranslation, .shortcut: return nil
        }
        guard !value.isEmpty else { return nil }
        self = .text(title: result.title, value: value, symbol: result.symbol, app: result.sourceApp)
    }

    @MainActor func draggingItem() -> NSDraggingItem {
        switch self {
        case .url(let url): return NSDraggingItem(pasteboardWriter: url as NSURL)
        case let .text(title, value, _, _):
            return NSDraggingItem(pasteboardWriter: ResultTextPromise(title: title, text: value))
        }
    }

    @MainActor var icon: NSImage? {
        switch self {
        case .url(let url) where url.isFileURL: return NSWorkspace.shared.icon(forFile: url.path)
        case .url: return NSImage(systemSymbolName: "link", accessibilityDescription: nil)
        case .text(_, _, let symbol, let app):
            return app.flatMap { AppIconCache.shared.icon(for: $0) } ?? NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
    }
}

/// A single pasteboard item offers inline text to editors and a .txt file to
/// file destinations. No temporary file or clipboard change is needed.
private final class ResultTextPromise: NSFilePromiseProvider {
    init(title: String, text: String) {
        let writer = TextFileWriter(title: title, text: text)
        super.init()
        fileType = UTType.plainText.identifier
        userInfo = writer // NSFilePromiseProvider.delegate is weak.
        delegate = writer
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.string]
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .string ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .string ? (userInfo as? TextFileWriter)?.text : super.pasteboardPropertyList(forType: type)
    }
}

private final class TextFileWriter: NSObject, NSFilePromiseProviderDelegate {
    let text: String
    private let filename: String
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 2
        return queue
    }()

    init(title: String, text: String) {
        self.text = text
        let separators = CharacterSet(charactersIn: "/:\\").union(.controlCharacters)
        let trimmed = title.components(separatedBy: separators).filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        var name = ""
        var length = 0
        for character in trimmed {
            length += String(character).utf8.count
            guard length <= 200 else { break }
            name.append(character)
        }
        filename = (name.isEmpty ? "Spotlight Han" : name) + ".txt"
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { filename }
    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { Self.queue }
    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        do {
            try Data(text.utf8).write(to: url, options: .withoutOverwriting)
            completionHandler(nil)
        } catch { completionHandler(error) }
    }
}
