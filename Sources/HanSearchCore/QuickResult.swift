import Foundation

public enum QuickAction: Hashable, Sendable {
    case copy(String), open(URL), note(String), shortcut(String), details(String)
}

public struct QuickResult: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let action: QuickAction
    public init(id: String, title: String, subtitle: String, symbol: String, action: QuickAction) {
        self.id = "quick:" + id; self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.action = action
    }
}

public struct PersonalRecord: Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let text: String
    public let folded: String
    public let symbol: String
    public let mode: SearchMode
    public let action: QuickAction
    public init(id: String, title: String, subtitle: String, text: String, symbol: String, mode: SearchMode, action: QuickAction) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.text = text
        self.folded = ChineseSearch.normalized(title + " " + subtitle + " " + text)
        self.symbol = symbol; self.mode = mode; self.action = action
    }
    public func result(query: String, mode: SearchMode) -> QuickResult? {
        guard mode == .all || mode == self.mode else { return nil }
        let terms = ChineseSearch.terms(ChineseSearch.normalized(query))
        guard !terms.isEmpty, terms.allSatisfy({ folded.contains($0) }) else { return nil }
        return QuickResult(id: id, title: title, subtitle: subtitle, symbol: symbol, action: action)
    }
}

public enum QuickProvider {
    public static func results(query: String) -> [QuickResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var items: [QuickResult] = []
        if Calculator.looksLikeExpression(query), let value = try? Calculator.evaluate(query) {
            let result = Calculator.format(value)
            items.append(QuickResult(id: "calculator", title: result, subtitle: query + "　↵ 複製答案", symbol: "equal", action: .copy(result)))
        }
        if let result = UnitConverter.convert(query) {
            items.append(QuickResult(id: "conversion", title: result, subtitle: query + "　↵ 複製結果", symbol: "arrow.left.arrow.right", action: .copy(result)))
        }
        if let url = URL(string: query), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            items.append(QuickResult(id: "url", title: query, subtitle: "在預設瀏覽器開啟", symbol: "globe", action: .open(url)))
        } else if !["doc", "docx", "pdf", "txt", "md", "xlsx", "pptx", "mp4", "mov", "mkv", "jpg", "jpeg", "png", "zip"].contains((query as NSString).pathExtension.lowercased()), query.range(of: #"^(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,63}(?::[0-9]{1,5})?$"#, options: .regularExpression) != nil, let url = URL(string: "https://" + query) {
            items.append(QuickResult(id: "url", title: query, subtitle: "在預設瀏覽器開啟", symbol: "globe", action: .open(url)))
        }
        if ["設定", "系统设置", "系統設定", "settings"].contains(query.lowercased()) {
            items.append(QuickResult(id: "settings", title: "系統設定", subtitle: "開啟 Mac 系統設定", symbol: "gearshape", action: .open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))))
        }
        return items
    }

    public static func webSearch(query: String) -> QuickResult? {
        var parts = URLComponents(string: "https://www.google.com/search")!
        parts.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = parts.url else { return nil }
        return QuickResult(id: "web", title: "搜尋網頁「\(query)」", subtitle: "Google · 按下 Return 後開啟瀏覽器", symbol: "magnifyingglass", action: .open(url))
    }
}
