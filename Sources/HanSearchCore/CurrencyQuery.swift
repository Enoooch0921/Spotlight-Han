import Foundation

public struct CurrencyQuery: Equatable, Sendable {
    public let amount: Double
    public let source: String
    public let target: String
    public static let defaultTargets = ["CNY", "USD", "JPY"]
    public static let supportedCodes = ["CNY", "USD", "JPY", "TWD", "EUR", "GBP", "HKD", "KRW", "AUD", "CAD", "SGD", "CHF", "NZD", "THB", "MYR", "VND", "IDR", "PHP", "INR"]
    private static let aliases: [String: String] = {
        var values: [String: String] = [:]
        let groups = [
            "TWD,NT,NT$,TB,台币,新台币,新臺币,臺币,新台幣,台幣", "CNY,RMB,人民币,人民幣", "USD,US$,美金,美元", "JPY,JP¥,日元,日币,日圆,日圓,日幣",
            "EUR,欧元,歐元", "GBP,英镑,英鎊", "KRW,韩元,韩币,韓元,韓幣", "HKD,HK$,港币,港元,港幣", "AUD,澳元,澳币,澳幣", "CAD,加元,加币,加幣",
            "SGD,新币,新加坡元,新幣", "CHF,瑞士法郎", "NZD,纽币,纽元,紐幣", "THB,泰铢,泰銖", "MYR,马币,馬幣", "VND,越南盾", "IDR,印尼盾", "PHP,菲律宾比索", "INR,印度卢比"
        ]
        for group in groups {
            let names = group.split(separator: ",").map(String.init)
            for name in names { values[ChineseSearch.normalized(name).uppercased()] = names[0] }
        }
        return values
    }()
    private static func code(_ name: String) -> String? {
        aliases[ChineseSearch.normalized(name.trimmingCharacters(in: .whitespacesAndNewlines)).uppercased()]
    }
    public static func cleanTargets(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap(code).filter { seen.insert($0).inserted }
    }
    /// Strict single explicit target; bare amounts use `requests` and the user's defaults instead.
    public static func parse(_ query: String) -> CurrencyQuery? {
        guard let explicit = explicitRequests(query), explicit.count == 1 else { return nil }
        return explicit[0]
    }
    public static func requests(_ query: String, defaultTargets: [String]) -> [CurrencyQuery] {
        if let explicit = explicitRequests(query) { return explicit }
        guard query.count <= 200, let amount = parseAmount(query) else { return [] }
        let chosen = cleanTargets(defaultTargets)
        let targets = chosen.isEmpty ? Self.defaultTargets : chosen
        let others = targets.filter { $0 != amount.source }
        return (others.isEmpty ? targets : others).map { CurrencyQuery(amount: amount.value, source: amount.source, target: $0) }
    }
    public static func isCurrencyQuery(_ query: String) -> Bool { !requests(query, defaultTargets: Self.defaultTargets).isEmpty }
    private static func explicitRequests(_ query: String) -> [CurrencyQuery]? {
        guard query.count <= 200 else { return nil }
        let input = ChineseSearch.simplified(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\s*(.*?)\s*(?:=|＝|(?i:\bto\b)|换算成|兑换成|换成|兑|转|到)\s*(.+?)\s*$"#
        if let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)), let left = Range(match.range(at: 1), in: input), let right = Range(match.range(at: 2), in: input) {
            return makeRequests(amountText: String(input[left]), targetsText: String(input[right]))
        }
        // Split after a complete amount+source, so both "3000tb rmb" and "3000 TWD CNY USD" work.
        let parts = input.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 2 else { return nil }
        for split in 1..<parts.count {
            if let requests = makeRequests(amountText: parts[..<split].joined(separator: " "), targetsText: parts[split...].joined(separator: " ")) { return requests }
        }
        return nil
    }
    private static func makeRequests(amountText: String, targetsText: String) -> [CurrencyQuery]? {
        guard let amount = parseAmount(amountText) else { return nil }
        let names = targetsText.split { $0.isWhitespace || ",，、/".contains($0) }.map(String.init)
        guard !names.isEmpty, names.allSatisfy({ code($0) != nil }) else { return nil }
        return cleanTargets(names).map { CurrencyQuery(amount: amount.value, source: amount.source, target: $0) }
    }
    private static func parseAmount(_ original: String) -> (value: Double, source: String)? {
        let input = ChineseSearch.simplified(original).trimmingCharacters(in: .whitespacesAndNewlines)
        let number = #"([+-]?(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?|\.\d+))"#
        guard let regex = try? NSRegularExpression(pattern: number), let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)), let range = Range(match.range, in: input) else { return nil }
        let prefix = input[..<range.lowerBound].trimmingCharacters(in: .whitespaces), suffix = input[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard prefix.isEmpty != suffix.isEmpty, let amount = Double(input[range].replacingOccurrences(of: ",", with: "")), amount.isFinite, abs(amount) <= 1e15, let source = code(prefix.isEmpty ? suffix : prefix) else { return nil }
        return (amount, source)
    }
    public func converted(using rates: [String: Double]) -> (amount: Double, rate: Double)? {
        guard let from = rates[source], let to = rates[target], from.isFinite, to.isFinite, from > 0, to > 0 else { return nil }
        let rate = to / from, result = amount * rate
        guard rate.isFinite, result.isFinite else { return nil }
        return (result, rate)
    }
    public static func money(_ amount: Double, code: String) -> String {
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal; formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        return code + " " + (formatter.string(from: NSNumber(value: amount)) ?? String(amount))
    }
}
