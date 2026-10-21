import SwiftUI
import HanSearchCore

struct SearchSupplementLabel: View {
    let match: SearchSupplement
    var body: some View {
        Label(L.format(match.kind == .zhuyinKeyboard ? "注音鍵位：%@" : "常用詞補充：%@", match.displayQuery), systemImage: match.kind == .zhuyinKeyboard ? "keyboard" : "character.book.closed")
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
}
