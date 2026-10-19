import Foundation

@main
struct LocalizationChecks {
    static func main() throws {
        let defaults = UserDefaults.standard
        defer { defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain) }
        func choose(_ language: String) { defaults.setVolatileDomain(["interfaceLanguage.v1": language], forName: UserDefaults.argumentDomain) }
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { fatalError(message) }
        }
        let data = try Data(contentsOf: Bundle.main.url(forResource: "Localization", withExtension: "json")!)
        let catalog = try JSONDecoder().decode([String: String].self, from: data)
        for (key, value) in catalog {
            check(key.components(separatedBy: "%@").count == value.components(separatedBy: "%@").count, "Placeholder mismatch: \(key)")
        }
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let path = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: language + ".lproj")!
            let strings = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: path)), format: nil) as! [String: String]
            check(strings.count == catalog.count, "Missing keys in \(language)")
            check(Set(strings.keys) == Set(catalog.keys), "Unexpected keys in \(language)")
        }
        choose("en")
        check(L.text("一般") == "General", "English static label")
        check(L.text("已連接 12 位聯絡人") == "Connected 12 contacts", "English dynamic status")
        check(L.format("自訂：%@", "⌘Space") == "Custom: ⌘Space", "Shortcut label")
        check(L.text("Spotlight Han 0.6.0 · 繁簡中文搜尋") == "Spotlight Han 0.6.0 · Traditional/Simplified Chinese search", "Specific template wins")
        check(L.text("hello　↵ 複製答案") == "hello  ↵ Copy answer", "Query suffix")
        choose("zh-Hans")
        check(L.text("介面語言") == "介面语言", "Simplified label")
        check(L.format("執行捷徑「%@」？", "備忘錄 Test") == "执行捷径「備忘錄 Test」？", "Preserve user text in formatted labels")
        check(L.text("正在讀取「教會活動」中的文件…") == "正在读取「教會活動」中的文件…", "Preserve folder name in dynamic status")
        check(L.text("紅果短劇電影.mp4") == "紅果短劇電影.mp4", "Never convert unknown content")
        choose("zh-Hant")
        check(L.text("介面語言") == "介面語言", "Traditional label")
        check(L.format("搜尋%@", "影片") == "搜尋影片", "Traditional template")
        print("Localization checks passed: 3 catalogs, \(catalog.count) keys; dynamic messages and user text preservation")
    }
}
