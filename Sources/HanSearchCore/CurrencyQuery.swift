import Foundation

public struct CurrencyQuery: Equatable, Sendable {
    public let amount: Double
    public let source: String
    public let target: String
    private static let aliases: [String: String] = {
        var values: [String: String] = [:]
        let groups = [
            "TWD,NT,NT$,台币,新台币,新臺币,臺币,新台幣,台幣", "CNY,RMB,人民币,人民幣", "USD,US$,美金,美元", "JPY,JP¥,日元,日币,日圆,日圓,日幣",
            "EUR,欧元,歐元", "GBP,英镑,英鎊", "KRW,韩元,韩币,韓元,韓幣", "HKD,HK$,港币,港元,港幣", "AUD,澳元,澳币,澳幣", "CAD,加元,加币,加幣",
            "SGD,新币,新加坡元,新幣", "CHF,瑞士法郎", "NZD,纽币,纽元,紐幣", "THB,泰铢,泰銖", "MYR,马币,馬幣", "VND,越南盾", "IDR,印尼盾", "PHP,菲律宾比索", "INR,印度卢比"
        ]
        for group in groups {
            let names = group.split(separator: ",").map(String.init)
            for name in names { values[ChineseSearch.normalized(name).uppercased()] = names[0] }
        }
        return values
    }()
    public static func parse(_ query: String) -> CurrencyQuery? {
        guard query.count <= 200 else { return nil }
        let input = ChineseSearch.simplified(query).trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\s*(.*?)\s*(?:=|＝|(?i:\bto\b)|换成|换算成|兑换成|兑|转|到)\s*(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)), let leftRange = Range(match.range(at: 1), in: input), let rightRange = Range(match.range(at: 2), in: input) else { return nil }
        let left = String(input[leftRange]), right = String(input[rightRange]).trimmingCharacters(in: .whitespaces)
        let number = #"([+-]?(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?|\.\d+))"#
        guard let amounts = try? NSRegularExpression(pattern: number), let found = amounts.firstMatch(in: left, range: NSRange(left.startIndex..., in: left)), let range = Range(found.range, in: left) else { return nil }
        let prefix = left[..<range.lowerBound].trimmingCharacters(in: .whitespaces), suffix = left[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard prefix.isEmpty != suffix.isEmpty, let amount = Double(left[range].replacingOccurrences(of: ",", with: "")), amount.isFinite, abs(amount) <= 1e15,
              let source = aliases[ChineseSearch.normalized(prefix.isEmpty ? suffix : prefix).uppercased()], let target = aliases[ChineseSearch.normalized(right).uppercased()] else { return nil }
        return CurrencyQuery(amount: amount, source: source, target: target)
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
