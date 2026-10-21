import Foundation

/// Explicit era names or a complete short year query; never extracts a year from a filename/title.
public enum TaiwanYearConverter {
    public struct Result: Sendable { public let text: String; public let source: String }
    public static func result(_ query: String) -> Result? {
        let input = ChineseSearch.simplified(query.precomposedStringWithCompatibilityMapping).trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.count <= 100 else { return nil }
        let pattern = #"^(民国|西元|公元|roc|ad)?\s*([0-9]{1,4})\s*年(?:\s*([0-9]{1,2})\s*月(?:\s*([0-9]{1,2})\s*(?:日|号))?)?\s*(?:(?:换算成|转换成|换成|转成|换算|转换|换|转|到|=|to)\s*(民国|西元|公元|roc|ad)\s*年?)?\s*[?？]?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else { return nil }
        func part(_ i: Int) -> String { Range(match.range(at: i), in: input).map { String(input[$0]).lowercased() } ?? "" }
        guard let year = Int(part(2)), year > 0 else { return nil }
        let era = part(1), target = part(5)
        let roc = era.isEmpty ? year < 1000 : ["民国", "roc"].contains(era)
        if !target.isEmpty, ["民国", "roc"].contains(target) == roc { return nil }
        let gregorian = roc ? year + 1911 : year
        guard (1912...9999).contains(gregorian) else { return nil }
        var suffix = ""
        if let month = Int(part(3)) {
            guard (1...12).contains(month) else { return nil }
            suffix = "\(month) 月"
            if let day = Int(part(4)) {
                let calendar = Calendar(identifier: .gregorian)
                guard let date = calendar.date(from: DateComponents(year: gregorian, month: month, day: day)), calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day else { return nil }
                suffix += " \(day) 日"
            }
            suffix = " " + suffix
        }
        return Result(text: (roc ? "西元 \(gregorian) 年" : "民國 \(gregorian - 1911) 年") + suffix, source: (roc ? "民國 \(year) 年" : "西元 \(year) 年") + suffix)
    }

    static func taskInput(_ query: String) throws -> String {
        let input = query.precomposedStringWithCompatibilityMapping
        let regex = try NSRegularExpression(pattern: #"(?:民國|民国)\s*([0-9]{1,4})\s*年"#)
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        var output = input
        for match in matches.reversed() {
            let numberRange = Range(match.range(at: 1), in: input)!, range = Range(match.range, in: input)!
            guard let year = Int(input[numberRange]), (1...8088).contains(year) else { throw NaturalTaskFailure.invalid("民國年份請填 1 到 8088。") }
            let tail = String(input[range.upperBound...])
            let datePattern = try NSRegularExpression(pattern: #"^\s*([0-9]{1,2})\s*月\s*([0-9]{1,2})\s*(?:日|號|号)"#)
            guard let dateMatch = datePattern.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)) else { throw NaturalTaskFailure.invalid("建立事項請補上完整日期，例如「民國115年12月5日開會」。") }
            let month = Int(tail[Range(dateMatch.range(at: 1), in: tail)!])!, day = Int(tail[Range(dateMatch.range(at: 2), in: tail)!])!
            let calendar = Calendar(identifier: .gregorian)
            guard let date = calendar.date(from: DateComponents(year: year + 1911, month: month, day: day)), calendar.component(.year, from: date) == year + 1911, calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day else { throw NaturalTaskFailure.invalid("日期或時間無效，請重新輸入。") }
            output.replaceSubrange(range, with: "\(year + 1911)年")
        }
        return output
    }
}
