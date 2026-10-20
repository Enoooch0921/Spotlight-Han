import SwiftUI

struct OnboardingWelcomePage: View {
    @State private var example = 0
    private let queries = ["紅果短劇", "教會活動", "hgdj"]
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text(queries[example]).font(.system(size: 23, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading)
                    OnboardingKey(text: "↵")
                }.padding(20)
                Divider().padding(.horizontal, 20)
                HStack(spacing: 16) {
                    Image(systemName: example == 1 ? "doc.text" : "play.rectangle.fill")
                        .font(.system(size: 28, weight: .light)).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        HighlightedText(text: example == 1 ? "教會活動計畫.docx" : "红果短剧", query: queries[example]).font(.headline)
                        if example == 1 {
                            HighlightedText(text: "為教会活动準備場地與設備。", query: queries[example])
                                .font(.callout).foregroundStyle(.secondary)
                        } else { Text(L.text("繁簡與 App 首字母，都能比對原始名稱。" )).font(.callout).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.left").foregroundStyle(.tertiary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.06)))
                .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
            HStack {
                Text(L.text("功能預覽・範例資料")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker(L.text("預覽範例"), selection: $example) {
                    Text(L.text("繁簡")).tag(0)
                    Text(L.text("內文")).tag(1)
                    Text(L.text("App 首字母")).tag(2)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 250)
            }.padding(.top, -12)
            HStack(alignment: .top, spacing: 28) {
                OnboardingFeatureLine(title: "保留原樣", detail: "以你習慣的字搜尋，不改動原始檔名與文字。", symbol: "character.book.closed")
                OnboardingFeatureLine(title: "看見依據", detail: "命中的字與內文片段會凸顯，方便判斷是不是要找的內容。", symbol: "text.magnifyingglass")
            }
            OnboardingNote(text: "App 可直接搜尋；文件內文與個人資料，需要先選範圍或連接來源。", symbol: "hand.raised")
        }.padding(.top, 4)
    }
}
