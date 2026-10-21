import SwiftUI
import HanSearchCore

struct OCRWorkProtectionSettingsView: View {
    @ObservedObject var store: SearchStore
    var body: some View {
        Group {
            Toggle(L.text("開啟工作保護"), isOn: $store.ocrProtectWork)
            Text(L.text("Logic Pro／Final Cut Pro 開啟時暫停背景 OCR。"))
                .font(.caption).foregroundStyle(.secondary)
            Toggle(L.text("音訊輸入或播放活動時也暫停 OCR"), isOn: $store.ocrProtectAudio).disabled(!store.ocrProtectWork)
            if store.ocrProtectWork, let app = store.ocrWorkActivity.protectedApp {
                Text(L.format("偵測到工作軟體：%@", app)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
