import SwiftUI
import AppKit

/// An explicit hover/click hint also works inside the nonactivating search panel.
struct ResultSourceHint: View {
    let source: String
    let explanation: String
    let heading: String
    let url: URL
    let pages: [Int]
    let isOCR: Bool
    @State private var presented = false
    @State private var pinned = false
    @State private var hoverTask: Task<Void, Never>?

    var body: some View {
        Button {
            hoverTask?.cancel()
            pinned.toggle()
            presented = pinned
        } label: {
            HStack(spacing: 4) {
                Text(source)
                Image(systemName: "info.circle").frame(width: 20, height: 20)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.caption2).foregroundStyle(.secondary)
        .accessibilityLabel(source).accessibilityHint(explanation)
        .onHover(perform: hoverChanged)
        .popover(isPresented: $presented, arrowEdge: .trailing) {
            ResultSourceInformation(source: source, heading: heading, explanation: explanation,
                                    url: url, pages: pages, isOCR: isOCR)
                .onHover(perform: hoverChanged)
        }
        .onChange(of: presented) { _, visible in if !visible { pinned = false } }
        .onDisappear { hoverTask?.cancel(); presented = false; pinned = false }
    }
    private func hoverChanged(_ hovering: Bool) {
        hoverTask?.cancel()
        guard !pinned, hovering != presented else { return }
        hoverTask = Task { @MainActor in
            // Allow the pointer to cross from the source label into the popover.
            do { try await Task.sleep(for: .milliseconds(hovering ? 180 : 350)) } catch { return }
            guard !Task.isCancelled else { return }
            presented = hovering
        }
    }
}

private struct ResultSourceInformation: View {
    let source: String
    let heading: String
    let explanation: String
    let url: URL
    let pages: [Int]
    let isOCR: Bool
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.text("結果資訊")).font(.headline)
            VStack(alignment: .leading, spacing: 5) {
                Text(heading).font(.callout.weight(.medium))
                Text(explanation).font(.caption).foregroundStyle(.secondary)
                Label(source, systemImage: "magnifyingglass")
                    .font(.caption).foregroundStyle(.secondary)
                if !pages.isEmpty {
                    Label(L.format("命中第 %@ 頁", pages.map(String.init).joined(separator: "、")), systemImage: "doc.text")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if isOCR { Label(L.text("OCR 辨識"), systemImage: "text.viewfinder").font(.caption).foregroundStyle(.secondary) }
            }
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text(L.text("完整路徑")).font(.caption).foregroundStyle(.secondary)
                Text(url.path).font(.caption).lineLimit(4).truncationMode(.middle).textSelection(.enabled)
            }
            HStack {
                Button(L.text("在 Finder 顯示")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Spacer(minLength: 8)
                Button(L.text(copied ? "已複製" : "複製路徑")) {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(url.path, forType: .string)
                }
            }.controlSize(.small)
        }.foregroundStyle(.primary).padding(16).frame(width: 320)
    }
}
