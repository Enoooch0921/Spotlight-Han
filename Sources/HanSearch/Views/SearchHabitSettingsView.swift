import SwiftUI

struct SearchHabitSettingsView: View {
    @ObservedObject var habits: SearchHabitStore
    var body: some View {
        Toggle(L.text("學習我的搜尋開啟習慣"), isOn: $habits.enabled)
        Text(L.text("常用結果會優先；學習紀錄只存在這台 Mac。"))
            .font(.caption).foregroundStyle(.secondary)
        HStack {
            Text(L.format("已記住 %@ 組開啟選擇", String(habits.history.entries.count))).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(L.text("清除學習紀錄")) { habits.clear() }.disabled(habits.history.entries.isEmpty)
        }
        if habits.saveFailed { Text(L.text("無法儲存搜尋習慣；本次仍可使用。" )).font(.caption).foregroundStyle(.orange) }
    }
}
