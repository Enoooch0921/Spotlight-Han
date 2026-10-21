import SwiftUI
import AppKit
import HanSearchCore

struct DocumentReadDetailsView: View {
    let issues: [DocumentReadIssue]
    let capped: Bool
    var totalIssues: Int? = nil
    var body: some View {
        if !issues.isEmpty || capped {
            DisclosureGroup(L.text("查看未完成的檔案與原因")) {
                VStack(alignment: .leading, spacing: 7) {
                    if let totalIssues, totalIssues > issues.count { Text(L.text("以下原因分類僅統計前 200 份明細；未完成總數請見上方。")).font(.caption2).foregroundStyle(.secondary) }
                    ForEach(DocumentReadReason.allCases, id: \.rawValue) { reason in
                        let count = issues.filter { $0.reason == reason }.count
                        if count > 0 { Text(L.format("%@：%@ 份", L.text(reason.title), String(count))).font(.caption) }
                    }
                    if capped { Text(L.text("已達 10,000 份文件上限，尚有文件未檢查；請選擇較小的資料夾。" )).font(.caption).foregroundStyle(.orange) }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(issues.prefix(200))) { issue in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(issue.url.lastPathComponent).font(.caption.weight(.medium)).lineLimit(1)
                                    Text(L.text(issue.reason.title)).font(.caption).foregroundStyle([.ocrDeferred, .ocrPending].contains(issue.reason) ? Color.secondary : Color.orange)
                                    Text(L.text(issue.reason.recoverySuggestion)).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    Text(issue.url.deletingLastPathComponent().path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
                                    .contextMenu { Button(L.text("在 Finder 顯示")) { NSWorkspace.shared.activateFileViewerSelecting([issue.url]) } }
                            }
                        }
                    }.frame(maxHeight: 220)
                    if issues.count > 200 { Text(L.text("明細顯示前 200 份，分類數量包含全部未完成文件。")).font(.caption2).foregroundStyle(.secondary) }
                }.padding(.vertical, 5)
            }
        }
    }
}
