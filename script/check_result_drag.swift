import AppKit
import HanSearchCore

@main struct ResultDragChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        for source in SystemSourceApp.allCases {
            // Some OS installations omit optional apps. Notes is a required fixture on macOS CI.
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.rawValue)
            if installed != nil || source == .notes {
                let icon = AppIconCache.shared.icon(for: source)
                precondition(icon?.isValid == true && icon === AppIconCache.shared.icon(for: source))
            }
        }
        precondition(SystemSettingsCatalog.results(query: "wifi").first?.sourceApp == .settings)
        let title = "../會議:紀錄"
        let body = "第一段 🗒️\n" + String(repeating: "背景資訊\n", count: 90) + "软体测试\n決議留在最後一行。"
        var scan = NotesReadState(identifiers: ["a", "b", "c"])
        scan.receive(id: "a", title: title, text: body, isTruncated: false)
        scan.receive(id: "b", title: "只有標題", text: "", isTruncated: true)
        scan.skip(id: "c", protected: true)
        for mode in [SearchMode.all, .notes] {
            let result = try PersonalRecord.search(scan.records, query: "軟體", mode: mode).first!
            precondition(result.subtitle != body && result.sourceApp == .notes)
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let provider = SearchResultDrag(result)!.draggingItem().item as! NSFilePromiseProvider
            precondition(board.writeObjects([provider]))
            precondition(board.string(forType: .string) == body)
            precondition(board.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil))
            let delegate = provider.delegate!
            let filename = delegate.filePromiseProvider(provider, fileNameForType: provider.fileType)
            precondition(filename == "會議 紀錄.txt")
            let dest = directory.appendingPathComponent(filename)
            if mode == .all {
                try await write(provider, to: dest)
                let stored = try Data(contentsOf: dest)
                precondition(stored == Data(body.utf8))
            } else {
                do { try await write(provider, to: dest); preconditionFailure("overwrote existing file") }
                catch { let stored = try Data(contentsOf: dest); precondition(stored == Data(body.utf8)) }
            }
        }
        let partial = try PersonalRecord.search(scan.records, query: "只有標題", mode: .notes).first!
        guard case let .text(_, value, _, .notes) = SearchResultDrag(partial) else { preconditionFailure() }
        precondition(value == "只有標題" && scan.records.count == 2)
        let calculator = QuickProvider.results(query: "24+18").first { $0.id == "quick:calculator" }!
        guard case let .text(_, answer, _, nil) = SearchResultDrag(calculator) else { preconditionFailure() }
        precondition(answer == "42")

        let panel = LauncherPanel(contentRect: NSRect(x: 50, y: 150, width: 350, height: 140),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        precondition(!panel.isMovable && !panel.isMovableByWindowBackground)
        let root = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        panel.contentView = root
        let top = ResultDragRegion.Region(frame: NSRect(x: 10, y: 80, width: 300, height: 44))
        let bottom = ResultDragRegion.Region(frame: NSRect(x: 10, y: 20, width: 300, height: 44))
        root.addSubview(top); root.addSubview(bottom)
        precondition(ResultDragRegion.Region.at(NSPoint(x: 150, y: 98), in: panel) === top)
        precondition(ResultDragRegion.Region.at(NSPoint(x: 255, y: 30), in: panel) === bottom)
        precondition(ResultDragRegion.Region.at(NSPoint(x: 255, y: 70), in: panel) == nil)
        print("PASS: All/Notes full text, external text and file-promise types, UTF-8 contents, safe filenames, collision, title-only/locked notes, copyable results, stationary panel and row hit boundaries")
    }

    private static func write(_ provider: NSFilePromiseProvider, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            provider.delegate!.filePromiseProvider(provider, writePromiseTo: url) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }
}
