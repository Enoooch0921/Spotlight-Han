import SwiftUI

enum OnboardingAppInput: String, CaseIterable {
    case pinyin, zhuyin
    var title: String { self == .pinyin ? "拼音首字母" : "注音首符號" }
    var query: String { self == .pinyin ? "jsj" : "ㄐㄙㄐ" }
    var explanation: String {
        self == .pinyin
            ? "輸入「計算機」的拼音首字母 jsj，也能找到 App。"
            : "輸入「計算機」每個字的第一個注音符號 ㄐㄙㄐ，也能找到 App。"
    }
    var instruction: String {
        self == .pinyin
            ? "計算機 → ji suan ji → jsj。也支援完整拼音 jisuanji；右鍵點結果可自訂縮寫。"
            : "計算機 → ㄐㄧˋ ㄙㄨㄢˋ ㄐㄧ → ㄐㄙㄐ。也支援完整注音；右鍵點結果可自訂縮寫。"
    }
}

struct OnboardingNote: View {
    let text: String
    var symbol = "info.circle"
    var body: some View {
        Label { Text(L.text(text)).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol) }
            .font(.callout).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
    }
}

struct OnboardingFeatureLine: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).frame(width: 24).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(L.text(title)).font(.headline)
                Text(L.text(detail)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct OnboardingKey: View {
    let text: String
    var body: some View {
        Text(text).font(.system(.body, design: .monospaced).weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.08)))
    }
}
