import SwiftUI

struct SearchHabitSettingsView: View {
    @ObservedObject var habits: SearchHabitStore
    var body: some View {
        Toggle(L.text("學習我的搜尋開啟習慣"), isOn: $habits.enabled)
        Text(L.text("成功開啟後才學習。同一搜尋詞反覆開啟的結果會優先；常用 App／備忘錄／檔案等類型只小幅加分。空白的 App 分類仍按名稱或最近開啟排列，行事曆仍保留日期排序。"))
            .font(.caption).foregroundStyle(.secondary)
        Text(L.text("只在本機保存加鹽雜湊識別碼、類型、次數與時間，不保存原始搜尋詞、檔名或內容、不上傳。最多保留 2,000 組，365 天未使用會淘汰；關閉後停止記錄與套用，清除會刪除既有學習紀錄。"))
            .font(.caption).foregroundStyle(.secondary)
        HStack {
            Text(L.format("已記住 %@ 組開啟選擇", String(habits.history.entries.count))).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(L.text("清除學習紀錄")) { habits.clear() }.disabled(habits.history.entries.isEmpty)
        }
        if habits.saveFailed { Text(L.text("無法儲存搜尋習慣；本次仍可使用。" )).font(.caption).foregroundStyle(.orange) }
    }
}
