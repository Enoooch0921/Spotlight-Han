import SwiftUI
import HanSearchCore

struct OCRIndexStatusView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        Form {
            Section(L.text("圖片與掃描 PDF")) {
                Toggle(L.text("使用 Apple Vision 辨識圖片與掃描 PDF"), isOn: $store.ocrEnabled).disabled(store.indexing)
                    .onChange(of: store.ocrEnabled) { _, _ in if !store.documentIndexRoots.isEmpty { store.rebuildIndex() } }
                Text(L.text("在本機辨識文字，搜尋結果顯示命中片段與 PDF 頁碼。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L.text("工作保護")) { OCRWorkProtectionSettingsView(store: store) }
            Section(L.text("電源與閒置")) {
                Toggle(L.text("只在閒置時辨識"), isOn: $store.ocrIdleOnly)
                Toggle(L.text("允許使用電池辨識（僅閒置且電量高於 30%）"), isOn: $store.ocrAllowBattery)
                Text(L.text("預設接電才辨識；使用中降速，閒置 90 秒後加快。低耗電模式或溫度升高時先等待。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text(L.text("首次大量辨識會增加耗電與溫度；可在概覽隨時暫停，已完成內容仍可搜尋。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
