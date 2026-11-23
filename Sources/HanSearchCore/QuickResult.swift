import Foundation

public enum QuickAction: Hashable, Sendable {
    case copy(String), open(URL), note(String), shortcut(String), details(String)
    case createTask(TaskPlan)
    case prepareTranslation(String)
}

public struct QuickResult: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let symbol: String
    public let action: QuickAction
    public let startDate: Date?
    public let endDate: Date?
    public let sourceApp: SystemSourceApp?
    public let noteText: String?
    public let supplement: SearchSupplement?
    public init(id: String, title: String, subtitle: String, symbol: String, action: QuickAction, startDate: Date? = nil, endDate: Date? = nil, supplement: SearchSupplement? = nil, noteText: String? = nil, sourceApp: SystemSourceApp? = nil) {
        self.id = "quick:" + id; self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.action = action
        self.startDate = startDate; self.endDate = endDate
        self.sourceApp = sourceApp
        self.noteText = noteText
        self.supplement = supplement
    }
    public func supplemented(by match: SearchSupplement) -> QuickResult {
        QuickResult(id: String(id.dropFirst("quick:".count)), title: title, subtitle: subtitle, symbol: symbol, action: action, startDate: startDate, endDate: endDate, supplement: match, noteText: noteText, sourceApp: sourceApp)
    }
}

public struct PersonalRecord: Sendable {
    /// Compile query-wide matching work once for a source snapshot, not once per
    /// note/contact/event. Titles and body text keep their existing match rules.
    public struct Query: Sendable {
        fileprivate struct Pattern: Sendable {
            let text: String
            let terms: [String]
            let model: ModelSearch.Query
            let phonetics: PhoneticSearch.Query
            init(_ text: String) {
                self.text = text
                terms = ChineseSearch.terms(ChineseSearch.normalized(text))
                model = ModelSearch.Query(text)
                phonetics = PhoneticSearch.Query(text)
            }
        }
        fileprivate let primary: Pattern
        fileprivate let alternatives: [(SearchSupplement, Pattern)]
        public init(_ text: String) {
            primary = Pattern(text)
            alternatives = TaiwanVocabulary.alternatives(for: text).map { ($0, Pattern($0.query)) }
        }
    }
    public let id: String
    public let title: String
    public let subtitle: String
    public let text: String
    public let folded: String
    private let phonetics: PhoneticSearch
    public let symbol: String
    public let mode: SearchMode
    public let action: QuickAction
    public let startDate: Date?
    public let endDate: Date?
    public init(id: String, title: String, subtitle: String, text: String, symbol: String, mode: SearchMode, action: QuickAction, startDate: Date? = nil, endDate: Date? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.text = text
        self.folded = ChineseSearch.normalized(title + " " + subtitle + " " + text)
        self.phonetics = PhoneticSearch(title)
        self.symbol = symbol; self.mode = mode; self.action = action
        self.startDate = startDate; self.endDate = endDate
    }
    public func result(query: String, mode: SearchMode, aliasMatch: Bool = false) -> QuickResult? {
        result(query: Query(query), mode: mode, aliasMatch: aliasMatch)
    }
    public func result(query: Query, mode: SearchMode, aliasMatch: Bool = false) -> QuickResult? {
        guard mode == .all || mode == self.mode else { return nil }
        if let result = primaryResult(query: query.primary, aliasMatch: aliasMatch) { return result }
        for (alternative, pattern) in query.alternatives {
            if let result = primaryResult(query: pattern, aliasMatch: false) { return result.supplemented(by: alternative) }
        }
        return nil
    }
    private func primaryResult(query: Query.Pattern, aliasMatch: Bool) -> QuickResult? {
        let terms = query.terms, model = query.model
        let literal = model.isIdentifier ? model.matches(title + "\n" + subtitle + "\n" + text) : terms.allSatisfy { folded.contains($0) }
        guard !terms.isEmpty, literal || phonetics.matches(query.phonetics, allowInitials: false) || aliasMatch else { return nil }
        let preview: String
        if self.mode == .notes {
            preview = SearchHighlight.excerpt(in: text, query: query.text)
        } else if self.mode == .mail && !ChineseSearch.matches(title + " " + subtitle, query: query.text) {
            preview = SearchHighlight.excerpt(in: text, query: query.text)
        } else { preview = subtitle }
        return QuickResult(id: id, title: title, subtitle: preview, symbol: symbol, action: action, startDate: startDate, endDate: endDate, noteText: self.mode == .notes ? text : nil, sourceApp: SystemSourceApp(self.mode))
    }

    public static func search(_ records: [PersonalRecord], query: String, mode: SearchMode,
                              calendarSort: CalendarResultSort = .upcoming, aliasTargets: Set<String> = [],
                              limit: Int = 50, cancellation: ProcessCancellation? = nil) throws -> [QuickResult] {
        func checkCancellation() throws {
            try Task.checkCancellation()
            if cancellation?.isCancelled == true { throw CancellationError() }
        }
        try checkCancellation()
        guard limit > 0 else { return [] }
        let prepared = Query(query)
        let ordered = calendarSort.sorted(records)
        var primary: [QuickResult] = [], supplementary: [QuickResult] = []
        for record in ordered {
            try checkCancellation()
            guard let result = record.result(query: prepared, mode: mode, aliasMatch: aliasTargets.contains("quick:" + record.id)) else { continue }
            if result.supplement == nil {
                primary.append(result)
                if primary.count == limit { break }
            } else if supplementary.count < limit { supplementary.append(result) }
        }
        try checkCancellation()
        return Array((primary + supplementary).prefix(limit))
    }
}

public enum QuickProvider {
    public static func results(query: String, defaultTemperatureScale: TemperatureScale = .celsius) -> [QuickResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var items: [QuickResult] = SystemSettingsCatalog.results(query: query)
        if let year = TaiwanYearConverter.result(query) {
            items.append(QuickResult(id: "year-conversion", title: year.text, subtitle: year.source + "　↵ 複製結果", symbol: "calendar", action: .copy(year.text)))
        }
        if query.range(of: #"^\s*[0-9]+(?:\.[0-9]+)?\s*斤\s*(?:換|换|轉|转|到|=|to|in|多少|幾|几)"#, options: [.regularExpression, .caseInsensitive]) != nil {
            let message = "「斤」有地區差異，請指定台斤（600 公克）或市斤（500 公克）。"
            items.append(QuickResult(id: "ambiguous-jin", title: message, subtitle: "例如：3台斤換公斤", symbol: "questionmark.circle", action: .details(message)))
        }
        if let plan = TaskCommandParser.parse(query) {
            let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
            let displayDate: Date
            if plan.kind == .alarm {
                do { displayDate = try ClockAlarmRequest.date(for: plan, now: Date()) }
                catch { return [QuickResult(id: "task-command", title: "此時間無法建立系統鬧鐘", subtitle: error.localizedDescription, symbol: "exclamationmark.circle", action: .details(error.localizedDescription))] }
            } else { displayDate = plan.start }
            let kind = plan.kind == .alarm ? "設定鬧鐘" : (plan.kind == .reminder ? "新增提醒事項" : "新增行事曆行程")
            let destination = plan.kind == .alarm ? "Apple 系統時鐘 · 分鐘精度，向上取整" : (plan.kind == .reminder ? "系統提醒事項（預設清單）" : "行事曆（預覽時選擇）")
            let duration = plan.kind == .event ? " · \(Int(plan.duration / 60)) 分鐘" : ""
            let actionHint = plan.kind == .alarm ? " · ↵ 建立" : " · ↵ 確認預覽"
            items.append(QuickResult(id: "task-command", title: kind + "：" + plan.title, subtitle: formatter.string(from: displayDate) + (plan.relativeDelay != nil ? " · 按 Return 起算" : "") + duration + " · " + destination + actionHint, symbol: plan.kind == .alarm ? "alarm" : (plan.kind == .reminder ? "checklist" : "calendar.badge.plus"), action: .createTask(plan), sourceApp: plan.kind == .alarm ? .clock : (plan.kind == .reminder ? .reminders : .calendar)))
            return items
        }
        if Calculator.looksLikeExpression(query), let value = try? Calculator.evaluate(query) {
            let result = Calculator.format(value)
            items.append(QuickResult(id: "calculator", title: result, subtitle: query + "　↵ 複製答案", symbol: "equal", action: .copy(result)))
        }
        if let result = UnitConverter.result(query, defaultTemperatureScale: defaultTemperatureScale) {
            items.append(QuickResult(id: result.automaticTemperature ? "temperature" : "conversion", title: result.text, subtitle: (result.automaticTemperature ? query + " → " + result.source : query) + (result.note.isEmpty ? "" : " · " + result.note) + "　↵ 複製結果", symbol: "arrow.left.arrow.right", action: .copy(result.text)))
        }
        if let url = URL(string: query), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            items.append(QuickResult(id: "url", title: query, subtitle: "在預設瀏覽器開啟", symbol: "globe", action: .open(url)))
        } else if !["doc", "docx", "pdf", "txt", "md", "xlsx", "pptx", "mp4", "mov", "mkv", "jpg", "jpeg", "png", "zip"].contains((query as NSString).pathExtension.lowercased()), query.range(of: #"^(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,63}(?::[0-9]{1,5})?$"#, options: .regularExpression) != nil, let url = URL(string: "https://" + query) {
            items.append(QuickResult(id: "url", title: query, subtitle: "在預設瀏覽器開啟", symbol: "globe", action: .open(url)))
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
