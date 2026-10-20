import SwiftUI

struct SearchRetentionEditor: View {
    @ObservedObject var store: SearchStore
    @State private var amount = ""
    @State private var secondsPerUnit = 60.0
    private func parsedSeconds(_ amount: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = store.interfaceLanguage.locale
        formatter.numberStyle = .decimal
        // Require the whole input to be numeric; NumberFormatter alone accepts a prefix.
        let decimal = formatter.decimalSeparator ?? "."
        let cleaned = amount.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: decimal, with: ".")
        guard let value = Double(cleaned), value.isFinite,
              (value * secondsPerUnit).isFinite, value * secondsPerUnit >= 1 else { return nil }
        return value * secondsPerUnit
    }
    var body: some View {
        Group {
            LabeledContent(L.text("保留上次搜尋多久")) {
                HStack(spacing: 8) {
                    TextField(L.text("自訂時長"), text: Binding(get: { amount }, set: {
                        amount = $0
                        if let value = parsedSeconds($0) { store.reopenRetention = value }
                    }))
                        .textFieldStyle(.roundedBorder).frame(width: 85)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel(L.text("自訂保留時長"))
                    Picker(L.text("時間單位"), selection: $secondsPerUnit) {
                        Text(L.text("秒")).tag(1.0)
                        Text(L.text("分鐘")).tag(60.0)
                    }.labelsHidden().fixedSize()
                }
            }
            if parsedSeconds(amount) == nil {
                Text(L.text("請輸入至少 1 秒的有效時長；目前仍沿用上次設定。"))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        // Changing units converts the existing duration; it does not change expiry.
        .onChange(of: secondsPerUnit) { _, _ in showSavedDuration() }
        .onAppear {
            secondsPerUnit = store.reopenRetention.truncatingRemainder(dividingBy: 60) == 0 ? 60 : 1
            showSavedDuration()
        }
    }
    private func showSavedDuration() {
        amount = (store.reopenRetention / secondsPerUnit).formatted(.number.locale(store.interfaceLanguage.locale).grouping(.never).precision(.fractionLength(0...8)))
    }
}
