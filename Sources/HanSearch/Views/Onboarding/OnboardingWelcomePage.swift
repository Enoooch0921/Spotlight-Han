import SwiftUI

struct OnboardingWelcomePage: View {
    @State private var example = 0
    private let queries = ["會議記錄", "台北出差", OnboardingAppInput.pinyin.query, OnboardingAppInput.zhuyin.query]
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
                    Image(systemName: example >= 2 ? "plus.forwardslash.minus" : "doc.text")
                        .font(.system(size: 28, weight: .light)).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        HighlightedText(text: example == 0 ? "会议记录.docx" : (example == 1 ? "出差計畫.docx" : "計算機"), query: queries[example]).font(.headline)
                        if example == 1 {
                            HighlightedText(text: "下週到台北出差，記得預訂車票與住宿。", query: queries[example])
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text(L.text(example == 0 ? "輸入繁體「會議記錄」，也能找到簡體檔名。" : (example == 2 ? OnboardingAppInput.pinyin.explanation : OnboardingAppInput.zhuyin.explanation)))
                                .font(.callout).foregroundStyle(.secondary)
                        }
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
                    Text(L.text("App 拼音")).tag(2)
                    Text(L.text("App 注音")).tag(3)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 360)
            }.padding(.top, -12)
            HStack(alignment: .top, spacing: 28) {
                OnboardingFeatureLine(title: "保留原樣", detail: "以你習慣的字搜尋，不改動原始檔名與文字。", symbol: "character.book.closed")
                OnboardingFeatureLine(title: "看見依據", detail: "命中的字與內文片段會凸顯，方便判斷是不是要找的內容。", symbol: "text.magnifyingglass")
            }
            OnboardingNote(text: "App 可直接搜尋；文件內文與個人資料，需要先選範圍或連接來源。", symbol: "hand.raised")
        }.padding(.top, 4)
    }
}
