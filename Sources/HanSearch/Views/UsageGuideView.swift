import SwiftUI

private struct GuideTopic: Identifiable {
    let id: Int
    let title: String
    let symbol: String
    let paragraphs: [String]
    static let all: [GuideTopic] = [
        GuideTopic(id: 0, title: "快速開始", symbol: "sparkles", paragraphs: [
            "在「一般」設定再次開啟時的行為與預設頁。可每次清空、一直保留，或在指定時間內接續搜尋。計時從收起面板開始，重新啟動 App 不會還原上次的搜尋文字。",
            "⌘1 App、⌘2 檔案、⌘3 捷徑、⌘4 剪貼板。Escape 收起面板。",
            "快捷鍵可開啟及收起面板。若要用 ⌘Space，先在系統設定 → 鍵盤 → 鍵盤快捷鍵 → Spotlight 關閉「顯示 Spotlight 搜尋」，再到 Han「搜尋與快捷鍵」按「使用 ⌘Space」。App 會記住你的選擇；若有衝突，保留原快捷鍵。"
        ]),
        GuideTopic(id: 1, title: "搜尋與快捷鍵", symbol: "magnifyingglass", paragraphs: [
            "右鍵點搜尋結果可設定自訂縮寫。應用程式頁可以新增分類、拖動 App 到分類、修改圖示與拖動分類順序。固定與最近開啟提供其他入口。",
            "中文名稱可用完整拼音／注音搜尋；只有 App 會自動比對首字母或注音首符號，例如計算機 jsj／ㄐㄙㄐ。檔名與個人資料標題不套用首字母，手動設定的縮寫仍有效。dl32 這類型號保留數字；聲調拼音請分開音節，例如 ji4 suan4 ji1。",
            "忘記切換輸入法時，可用標準注音鍵位找 App，例如 rnr 或 ru4nj04ru 找計算機。必須完整對上 App 的注音或至少三個首符號，不套用到文件內文；原始查詢命中始終優先。",
            "常用詞互搜限於隨身碟／U盤、列印／打印、印表機／打印機、滑鼠／鼠標、軟體／軟件、硬體／硬件。補充結果標示實際比對詞，使用習慣與日期排序不會把它們移到原始命中之前。",
            "右鍵點 App、檔案或個人資料結果，選「自訂搜尋縮寫…」。縮寫與項目識別資料只存在這台 Mac；不會上傳。刪除縮寫請在同一視窗留空儲存。計算器與新增事項指令仍優先。",
            "成功開啟後才學習。同一搜尋詞反覆開啟的結果會優先；常用 App／備忘錄／檔案等類型只小幅加分。空白的 App 分類仍按名稱或最近開啟排列，行事曆仍保留日期排序。",
            "只在本機保存加鹽雜湊識別碼、類型、次數與時間，不保存原始搜尋詞、檔名或內容、不上傳。最多保留 2,000 組，365 天未使用會淘汰；關閉後停止記錄與套用，清除會刪除既有學習紀錄。"
        ]),
        GuideTopic(id: 2, title: "檔案與索引", symbol: "folder", paragraphs: [
            "OCR 會增加耗電與溫度，預設僅接電時辨識；使用中降低頻率，閒置後加快。低耗電或溫度升高會等待，可在索引設定暫停或調整。",
            "圖片與掃描 PDF 使用 Apple Vision 在本機背景辨識；可在索引設定暫停、繼續或關閉。結果標示 OCR 與 PDF 頁碼，辨識不會修改原檔或上傳圖片。",
            "常用資料夾預選下載、桌面、影片、音樂、圖片、文件；授權後才開始讀取。iCloud 在選擇視窗加入，只處理已下載檔案，不自動下載整個雲端。照片圖庫請先匯出圖片。",
            "快速檔名清單找名稱與影片，Han 全文索引找文件與圖片文字；常用範圍可一次授權建立兩種索引，也可各自管理。「全部」合併兩種結果。",
            "Han 文件索引預設保存在 ~/Library/Application Support/Spotlight Han/Index/，只在本機保存擷取的文字，不上傳。預設容量 500 MB，可在設定更改；索引未額外加密。",
            "支援 Word、PDF、PPTX、XLSX、文字及常見圖片。開啟 OCR 時圖片與 PDF 單檔 100 MB，其他文件 20 MB、文字 8 MB；PDF 最多 2,000 頁。略過 Library、隱藏檔與套件內容，不跟隨符號連結。",
            "背景更新啟用時，文件變更會觸發增量更新，另每 15 分鐘重新檢查。未變動的文件沿用既有內文，重新開啟 App 不必全部重建。",
            "「讀取不完整」仍可搜尋已完成片段；明細區分雲端未下載、OCR 待接續、關閉、逾時或失敗。成功辨識但沒有文字的照片不算失敗。舊格式可轉成 PPTX／XLSX。",
            "移除搜尋範圍會清除對應的 Han 內文索引；清除並重建會重新擷取原檔。這些操作不刪除原始文件。Spotlight 補充搜尋預設關閉，開啟後的補充結果仍受系統索引限制。",
            "首次確認範圍，之後沿用資料夾書籤；未授權前不自動掃描。勾選常用範圍再選使用者資料夾，可一次加入下載、桌面、影片、音樂、圖片、文件；各種媒體只處理支援的檔案類型。"
        ]),
        GuideTopic(id: 3, title: "資料來源", symbol: "square.stack.3d.up", paragraphs: [
            "請到「資料來源」集中連接備忘錄、聯絡人、行事曆、提醒事項等。授權由 macOS 管理；「全部重新讀取」只更新已連接來源。",
            "授權有效時安靜更新，不會反覆詢問。行事曆／提醒事項每5分鐘及收到變更後更新；其他已連接來源與文件索引每15分鐘更新。權限失效會暫停並顯示狀態，等你主動重新連接。",
            "資料只留在本次執行的記憶體；搜尋不修改或上傳；只有你確認新增指令時才寫入行事曆、提醒事項或系統時鐘。系統授權由你確認。移除來源會清除 App 內的搜尋副本；撤銷系統授權請至系統設定。"
        ]),
        GuideTopic(id: 4, title: "翻譯與工具", symbol: "character.bubble", paragraphs: [
            "設定30分鐘後的鬧鐘\n提醒我明天上午9點交報告\n明天下午3點開會30分鐘",
            "使用 Apple 本機翻譯（macOS 15 以上）。語言已下載時自動顯示；缺少語言時，選取翻譯結果按 Return 開啟語言視窗，再進入系統語言下載設定。下載後可跨 App 共用。原查詢的檔案與 App 結果仍保留。",
            "例如：3公斤換成磅、5公里多少公尺、32°F=°C。溫度可只輸入37攝氏度或37度，自動顯示另一種溫標。",
            "台灣單位與年份可輸入20坪換平方公尺、3台斤換公斤、115年；年份結果保留一般搜尋。只寫「斤」不猜地區，需指定台斤或市斤。",
            "重複事項：cal或提醒＋Tab，輸入每週三晚上七點上課、每月5號提醒繳房租；預覽可改成每天、每週、每月或不重複，並調整間隔。未設定結束日期；每月沒有該日會略過。",
            "貨幣可輸入 3000tb=rmb、3000tb rmb、nt3000 = rmb。只輸入 3000tb 或 3000台幣，會顯示下方選取的目標；也可明寫 3000tb=rmb,usd,jpy。參考匯率每日更新，結果標示資料時間及過期快取，非銀行成交價。",
            "也可用國名：3000NT=馬來西亞、3000NT 馬來、3000NT=Malaysia；New Zealand、South Korea 等英文國名也支援。",
            "行程與提醒：輸入 cal／行事曆或提醒／rem，按 Tab 後輸入時間和事項。Return 進入確認預覽，按「確認建立」或 ⌘Return 才寫入。行程可選擇 Han 預設行事曆及當次目的地；提醒使用系統預設清單。系統鬧鐘仍按 Return 建立，首次需連接內附捷徑。"
        ])
    ]
}

struct UsageGuideView: View {
    @ObservedObject var store: SearchStore
    @State private var selection: Int? = 0
    var body: some View {
        NavigationSplitView {
            List(GuideTopic.all, selection: $selection) { topic in
                Label(L.text(topic.title), systemImage: topic.symbol).tag(topic.id)
            }.listStyle(.sidebar).navigationSplitViewColumnWidth(min: 165, ideal: 185, max: 210)
        } detail: {
            let topic = GuideTopic.all.first { $0.id == selection } ?? GuideTopic.all[0]
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L.text("使用說明")).font(.caption).foregroundStyle(.secondary)
                    Text(L.text(topic.title)).font(.largeTitle.weight(.semibold))
                    ForEach(Array(topic.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(L.text(paragraph)).font(.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    Divider()
                    Link(L.text("GitHub 專案與原始碼"), destination: URL(string: "https://github.com/Enoooch0921/Spotlight-Han")!)
                }.frame(maxWidth: 640, alignment: .leading).padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .environment(\.locale, store.interfaceLanguage.locale)
        .id(store.interfaceLanguage.rawValue)
        .background(AuxiliaryWindowLifecycle { visible in
            store.helpPresented = visible
            store.settingsVisibilityChanged?(visible || store.settingsPresented || store.onboardingPresented)
        })
    }
}
