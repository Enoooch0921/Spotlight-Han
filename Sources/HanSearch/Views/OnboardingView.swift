import SwiftUI

struct OnboardingView: View {
    @ObservedObject var store: SearchStore
    let finish: () -> Void
    @State private var step = 0
    @Environment(\.openSettings) private var openSettings
    private let titles = ["一個搜尋框，找回你要的東西", "讓 Han 配合你的習慣", "選擇你想搜尋的範圍"]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Spotlight Han", systemImage: "magnifyingglass").font(.headline)
                Spacer()
                Text(L.format("第 %@／3 步", String(step + 1))).font(.callout).foregroundStyle(.secondary)
            }.padding(.bottom, 24)
            Text(L.text(titles[step])).font(.system(size: 28, weight: .semibold)).padding(.bottom, 10)
            Group {
                switch step {
                case 0: welcome
                case 1: preferences
                default: setup
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider().padding(.vertical, 18)
            HStack {
                Button(L.text("稍後設定"), action: finish).buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                if step > 0 { Button(L.text("上一步")) { step -= 1 } }
                Button(L.text(step == 2 ? "開始使用" : "繼續")) {
                    if step < 2 { step += 1 } else { finish() }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 740, height: 650)
            .environment(\.locale, store.interfaceLanguage.locale)
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(L.text("不用猜檔名是繁體還是簡體，也不用再翻好幾層資料夾。"))
                .font(.title3).foregroundStyle(.secondary).padding(.bottom, 8)
            feature("繁簡都找得到", detail: "輸入「紅果短劇」，也能找到已安裝的「红果短剧」。", symbol: "character.book.closed")
            feature("找檔名，也找文件裡的字", detail: "選取資料夾後，可搜尋 Word、文字 PDF、PPTX、Excel 內文與命中片段。", symbol: "doc.text.magnifyingglass")
            feature("常用小事，順手完成", detail: "計算、每日匯率、翻譯，以及預覽後建立行程與提醒。", symbol: "sparkles")
            Text(L.text("首次不會自動掃描整個 Mac，也不會一次要求所有隱私權限。"))
                .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
        }.padding(.top, 12)
    }
    private var preferences: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.text("預設保留上次搜尋 3 分鐘；你可以自訂時間及再次開啟的頁面。"))
                .foregroundStyle(.secondary)
            Form { SearchReopenSettingsView(store: store) }.formStyle(.grouped)
            HStack {
                Label(L.format("目前快捷鍵：%@", store.hotkeyNotice), systemImage: "keyboard")
                Spacer()
                Button(L.text("設定快捷鍵…")) { settings(.search) }
            }
            Text(L.text("想用 ⌘Space，可在設定中直接前往 macOS 關閉原 Spotlight 快捷鍵，再指定給 Han。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var setup: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L.text("先選常用資料夾即可。需要備忘錄或行事曆時，再連接對應來源。"))
                .foregroundStyle(.secondary).padding(.bottom, 4)
            setupRow("快速找檔名與影片", detail: "選擇下載、文件、影片等常用位置。", symbol: "folder", ready: !store.catalogRoots.isEmpty, action: {
                if store.catalogRoots.isEmpty { store.chooseCatalogFolder() } else { settings(.files) }
            })
            setupRow("搜尋文件內文", detail: "Han 自建本機索引，重新啟動也能接續搜尋。", symbol: "doc.text", ready: !store.documentRoots.isEmpty, action: {
                if store.documentRoots.isEmpty { store.chooseFolder() } else { settings(.files) }
            })
            setupRow("連接備忘錄與行事曆等來源", detail: "由你選擇要連接的 App，授權後可背景更新。", symbol: "square.stack.3d.up", ready: store.sourceHealth.contains { $0.key != .contents && $0.key != .names && $0.value.hasSnapshot }, action: { settings(.sources) })
            Text(L.text("可以稍後再設定：設定頁左下角有使用說明，「更新與關於」可重新開啟這份引導。"))
                .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
        }.padding(.top, 8)
    }
    private func feature(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 25)).foregroundStyle(.tint).frame(width: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(L.text(title)).font(.headline)
                Text(L.text(detail)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func setupRow(_ title: String, detail: String, symbol: String, ready: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title2).frame(width: 32).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(L.text(title)).font(.headline)
                Text(L.text(detail)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if ready { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel(L.text("已設定")) }
            Button(L.text(ready ? "管理…" : "設定…"), action: action)
        }.padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
    }
    private func settings(_ page: SettingsPage) { store.settingsPage = page; openSettings() }
}
