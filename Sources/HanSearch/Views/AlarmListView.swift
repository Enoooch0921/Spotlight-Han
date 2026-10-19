import SwiftUI

struct AlarmListView: View {
    var connect: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("使用 Apple 系統時鐘", systemImage: "alarm").font(.headline)
            Text("輸入「設定30分鐘後的鬧鐘」，先預覽時間，按 Return 交給系統時鐘新增。")
            HStack {
                Button("連接系統時鐘") { connect() }
                Button("開啟時鐘") { SystemClockService.openClock() }
            }
            Text("首次只需加入一個預先做好的捷徑，不用自己編輯。鬧鐘以分鐘為精度，會向上取整；支援下一次的指定時分，更晚日期請用提醒事項。鬧鐘由系統時鐘管理，這裡不顯示或儲存鬧鐘清單。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
