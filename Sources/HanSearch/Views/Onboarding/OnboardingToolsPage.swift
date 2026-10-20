import SwiftUI

struct OnboardingToolsPage: View {
    let settings: (SettingsPage) -> Void
    @State private var tool = 0
    private let examples = ["36 * 24", "3000nt = 馬來西亞", "明天下午3點開會30分鐘", "hello", "jsj"]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Picker(L.text("工具範例"), selection: $tool) {
                Text(L.text("計算")).tag(0)
                Text(L.text("匯率")).tag(1)
                Text(L.text("行程提醒")).tag(2)
                Text(L.text("翻譯")).tag(3)
                Text(L.text("縮寫")).tag(4)
            }.pickerStyle(.segmented).labelsHidden()
            GroupBox {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        if tool == 2 { OnboardingKey(text: "cal ⇥") }
                        Text(examples[tool]).font(.system(size: 19, weight: .medium)).textSelection(.enabled)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tool == 3 ? "你好" : L.text(resultTitle)).font(.system(size: tool == 0 ? 38 : 23, weight: .medium))
                        Text(L.text(resultDetail)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                }.padding(16)
            }
            Text(L.text("操作示範・不會執行或新增資料")).font(.caption).foregroundStyle(.secondary)
            OnboardingFeatureLine(title: instructionTitle, detail: instructionDetail, symbol: tool == 2 ? "calendar.badge.plus" : "lightbulb")
            if tool == 2 {
                HStack(spacing: 10) {
                    OnboardingKey(text: "Return")
                    Text(L.text("預覽")).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Text(L.text("確認建立")).fontWeight(.medium)
                }.font(.callout)
            }
            if tool == 3 { Button(L.text("準備翻譯語言…")) { settings(.tools) } }
        }
    }
    private var resultTitle: String {
        switch tool { case 0: return "864"; case 1: return "TWD → MYR"; case 2: return "開會 · 明天 15:00–15:30"; case 3: return "你好"; default: return "計算機" }
    }
    private var resultDetail: String {
        switch tool {
        case 0: return "四則運算、括號、百分比，也能轉換常見單位。"
        case 1: return "可輸入國家名稱，不用先知道貨幣代碼。結果會標示每日參考匯率的資料日期。"
        case 2: return "預覽中可核對時間、內容與目的行事曆；確認後才寫入。"
        case 3: return "使用 Apple 本機翻譯，需要先準備所選語言模型。"
        default: return "首字母只套用 App；文件標題與內文維持文字比對。"
        }
    }
    private var instructionTitle: String {
        switch tool { case 0: return "直接輸入算式或單位"; case 1: return "也能一次顯示多種貨幣"; case 2: return "先輸入 cal 或提醒，再按 Tab"; case 3: return "翻譯與搜尋可以並存"; default: return "拼音、注音，也可以自訂" }
    }
    private var instructionDetail: String {
        switch tool {
        case 0: return "例如 36 * 24、10 cm in inch。選取計算結果按 Return，即可複製。"
        case 1: return "3000tb rmb、nt3000 = usd 都可以；設定裡可勾選多個預設目標。免費匯率每日更新，並非銀行成交價。"
        case 2: return "輸入自然語言時間與事項，再按 Return 看預覽。提醒也可用 rem；系統鬧鐘需先連接時鐘捷徑。"
        case 3: return "下載語言可能需要一些時間；翻譯顯示在搜尋結果下方，原本的檔案與 App 搜尋不受影響。"
        default: return "例如「計算機」可用 jsj、jisuanji 或 ㄐㄧㄙㄨㄢㄐㄧ 搜尋。右鍵點結果，還能自訂縮寫。"
        }
    }
}
