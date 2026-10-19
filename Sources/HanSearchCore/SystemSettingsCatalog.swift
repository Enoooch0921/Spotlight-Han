import Foundation

/// A local, explicit registry of common settings panes. URLs contain fixed identifiers only.
/// Identifiers are checked against macOS 26 system extensions; later systems need UI verification.
public enum SystemSettingsCatalog {
    private struct Pane: Sendable {
        let id: String
        let title: String
        let aliases: [String]
        let symbol: String
        let searchable: [String]
        init(_ id: String, _ title: String, _ aliases: [String], _ symbol: String) {
            self.id = id; self.title = title; self.aliases = aliases; self.symbol = symbol
            self.searchable = ([title] + aliases).map(SystemSettingsCatalog.normalized)
        }
    }
    private static let panes: [Pane] = [
        Pane("com.apple.settings.PrivacySecurity.extension", "隱私與安全性", ["隱私", "隱私安全性", "安全性", "安全", "privacy", "security", "privacy and security"], "hand.raised"),
        Pane("com.apple.wifi-settings-extension", "Wi-Fi", ["wifi", "wi fi", "無線網路", "無線網絡", "無線", "无线网络", "wireless"], "wifi"),
        Pane("com.apple.BluetoothSettings", "藍牙", ["藍芽", "bluetooth", "bt"], "dot.radiowaves.left.and.right"),
        Pane("com.apple.Network-Settings.extension", "網路", ["網絡", "网络", "network", "ethernet", "乙太網路"], "network"),
        Pane("com.apple.Keyboard-Settings.extension", "鍵盤", ["keyboard", "快捷鍵", "hotkey", "shortcuts"], "keyboard"),
        Pane("com.apple.Sound-Settings.extension", "聲音", ["sound", "audio", "音量", "volume", "音效"], "speaker.wave.2"),
        Pane("com.apple.Displays-Settings.extension", "顯示器", ["display", "displays", "螢幕", "屏幕", "解析度", "resolution"], "display"),
        Pane("com.apple.Localization-Settings.extension", "語言與地區", ["語言", "語言地區", "地區", "language", "region", "translation", "翻譯"], "character.bubble"),
        Pane("com.apple.Accessibility-Settings.extension", "輔助使用", ["輔助功能", "accessibility", "voiceover"], "accessibility"),
        Pane("com.apple.Notifications-Settings.extension", "通知", ["notification", "notifications"], "bell"),
        Pane("com.apple.Appearance-Settings.extension", "外觀", ["appearance", "dark mode", "深色模式", "主題"], "circle.lefthalf.filled"),
        Pane("com.apple.Desktop-Settings.extension", "桌面與 Dock", ["桌面", "桌面dock", "dock", "desktop"], "dock.rectangle"),
        Pane("com.apple.Sharing-Settings.extension", "共享", ["分享", "sharing", "檔案共享", "file sharing"], "square.and.arrow.up"),
        Pane("com.apple.Focus-Settings.extension", "專注模式", ["專注", "focus", "勿擾", "do not disturb"], "moon"),
        Pane("com.apple.Software-Update-Settings.extension", "軟體更新", ["軟件更新", "系統更新", "software update", "update"], "gearshape.arrow.triangle.2.circlepath"),
        Pane("com.apple.settings.Storage", "儲存空間", ["儲存", "存儲", "存儲空間", "storage", "磁碟空間", "disk space"], "internaldrive"),
        Pane("com.apple.LoginItems-Settings.extension", "登入項目與延伸功能", ["登入項目", "登錄項", "開機啟動", "自動啟動", "login items", "startup", "extensions"], "person.crop.circle.badge.checkmark"),
        Pane("com.apple.Trackpad-Settings.extension", "觸控式軌跡板", ["觸控板", "觸摸板", "trackpad"], "rectangle.and.hand.point.up.left"),
        Pane("com.apple.Mouse-Settings.extension", "滑鼠", ["mouse", "鼠標"], "computermouse"),
        Pane("com.apple.Date-Time-Settings.extension", "日期與時間", ["日期", "時間", "date", "time", "時區", "timezone"], "clock"),
        Pane("com.apple.Wallpaper-Settings.extension", "背景圖片", ["桌布", "壁紙", "wallpaper", "背景"], "photo"),
        Pane("com.apple.Users-Groups-Settings.extension", "使用者與群組", ["使用者", "用戶", "users", "groups", "帳號", "賬戶"], "person.2")
    ]
    private static func normalized(_ text: String) -> String {
        ChineseSearch.normalized(text).unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    public static func results(query: String) -> [QuickResult] {
        var query = normalized(query)
        guard !query.isEmpty else { return [] }
        let rootNames = ["設定", "設置", "系統設定", "系統設置", "settings", "system settings", "system preferences"].map(normalized)
        if rootNames.contains(query) {
            return [QuickResult(id: "settings", title: "系統設定", subtitle: "開啟 Mac 系統設定", symbol: "gearshape", action: .open(URL(fileURLWithPath: "/System/Applications/System Settings.app")))]
        }
        for prefix in ["打開", "開啟", "前往", "系統設定", "系統設置", "open ", "system settings ", "settings "].map(normalized).sorted(by: { $0.count > $1.count }) {
            if query.hasPrefix(prefix) { query.removeFirst(prefix.count); query = query.trimmingCharacters(in: .whitespaces) }
        }
        for suffix in ["設定", "設置", " settings"].map(normalized) where query.hasSuffix(suffix) && query.count > suffix.count {
            query.removeLast(suffix.count); query = query.trimmingCharacters(in: .whitespaces)
        }
        guard !query.isEmpty, query.count >= 2 || query.unicodeScalars.contains(where: { $0.value > 127 }) else { return [] }
        let terms = query.split(separator: " ").map(String.init)
        return panes.compactMap { pane -> (Int, QuickResult)? in
            let aliases = pane.searchable
            let haystack = aliases.joined(separator: " ")
            guard terms.allSatisfy({ haystack.contains($0) }) else { return nil }
            let score = aliases.contains(query) ? 0 : aliases.contains(where: { $0.hasPrefix(query) }) ? 1 : 2
            let url = URL(string: "x-apple.systempreferences:" + pane.id)!
            return (score, QuickResult(id: "system-settings:" + pane.id, title: pane.title, subtitle: "系統設定 · 按 Return 開啟此頁面", symbol: pane.symbol, action: .open(url)))
        }.sorted { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1.id < $1.1.id) }.prefix(6).map(\.1)
    }
}
