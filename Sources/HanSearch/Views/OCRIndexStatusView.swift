import SwiftUI
import HanSearchCore

struct OCRIndexStatusView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L.text("使用 Apple Vision 辨識圖片與掃描 PDF"), isOn: $store.ocrEnabled).disabled(store.indexing)
                .onChange(of: store.ocrEnabled) { _, _ in if !store.documentIndexRoots.isEmpty { store.rebuildIndex() } }
            Text(L.text("在本機背景辨識繁簡中文與英文，結果標示 OCR、片段及 PDF 頁碼；不修改原檔、不保存辨識圖片。"))
                .font(.caption).foregroundStyle(.secondary)
            if store.ocrEnabled {
                Label(L.text(store.ocrWorkDecision.title), systemImage: "leaf")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup(L.text("OCR 效能與電池")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(L.text("只在閒置時辨識"), isOn: $store.ocrIdleOnly)
                        Toggle(L.text("允許使用電池辨識（僅閒置且電量高於 30%）"), isOn: $store.ocrAllowBattery)
                        Text(L.text("預設只在接電時 OCR：使用中降低頻率，閒置 90 秒後加快；低耗電模式或溫度升高時等待。條件改善後約 30 秒內自動續讀，不阻止 Mac 睡眠。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 6)
                }
                Text(L.text("首次辨識大量圖片可能需較久，會暫時增加 CPU、耗電及溫度。每次只處理一頁，系統狀態改變後在頁面之間調整；可隨時暫停索引，已完成內容仍可搜尋。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !store.spotlightSupplement {
                Button(L.text("開啟 Spotlight 補充（混合搜尋）")) { store.spotlightSupplement = true }.controlSize(.small)
            }
            if store.indexing && !store.indexCurrentFile.isEmpty {
                HStack {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.text(store.indexRecognizing ? "正在辨識圖片文字…" : "正在讀取文件文字…")).font(.caption)
                        Text(store.indexCurrentFile).font(.caption).lineLimit(1).truncationMode(.middle)
                        if store.indexTotalPages > 0 {
                            Text(L.format("目前第 %@／%@ 頁", String(store.indexCurrentPage), String(store.indexTotalPages))).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text(L.format("OCR 已處理 %@ 頁，涵蓋 %@ 份檔案", String(store.indexSnapshot.ocrPages), String(store.indexSnapshot.ocrFiles)))
                .font(.caption).foregroundStyle(.secondary)
            if store.indexSnapshot.deferredOCR > 0 {
                Text(L.format("%@ 份文件因節能條件等待，符合條件後自動接續", String(store.indexSnapshot.deferredOCR))).font(.caption).foregroundStyle(.secondary)
            }
            if store.indexSnapshot.pendingOCR > 0 {
                Text(L.format("尚有 %@ 份文件待接續，已完成部分可先搜尋", String(store.indexSnapshot.pendingOCR))).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
