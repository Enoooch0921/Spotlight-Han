import Foundation

public enum MathError: Error, LocalizedError {
    case invalid, undefined, tooComplex
    public var errorDescription: String? {
        switch self {
        case .invalid: return "請輸入有效的算式"
        case .undefined: return "此算式沒有有限的實數結果"
        case .tooComplex: return "算式過長或括號層數太多"
        }
    }
}

public enum Calculator {
    public static func evaluate(_ input: String) throws -> Double {
        guard input.count <= 200 else { throw MathError.tooComplex }
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("=") { text.removeFirst() }
        text = text.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "π", with: "pi")
            .replacingOccurrences(of: "√", with: "sqrt")
        var parser = Parser(chars: Array(text.lowercased().filter { !$0.isWhitespace }))
        let result = try parser.sum()
        guard parser.i == parser.chars.count else { throw MathError.invalid }
        guard result.isFinite else { throw MathError.undefined }
        return result
    }

    public static func looksLikeExpression(_ text: String) -> Bool {
        if text.hasPrefix("=") { return true }
        if text.range(of: #"^\d{4}[-/]\d{1,2}[-/]\d{1,2}$"#, options: .regularExpression) != nil { return false }
        return text.contains(where: { $0.isNumber }) && text.contains(where: { "+-*/×÷^%√()".contains($0) })
    }

    public static func format(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = abs(number) >= 1e15 || (number != 0 && abs(number) < 1e-9) ? .scientific : .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 12
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }

    private struct Parser {
        let chars: [Character]
        var i = 0
        var depth = 0
        mutating func take(_ char: Character) -> Bool {
            guard i < chars.count, chars[i] == char else { return false }; i += 1; return true
        }
        mutating func sum() throws -> Double {
            var v = try product()
            while i < chars.count {
                if take("+") { v += try product() }
                else if take("-") { v -= try product() }
                else { break }
            }
            return v
        }
        mutating func product() throws -> Double {
            var v = try unary()
            while i < chars.count {
                if take("*") { v *= try unary() }
                else if take("/") { let d = try unary(); guard d != 0 else { throw MathError.undefined }; v /= d }
                else { break }
            }
            return v
        }
        mutating func unary() throws -> Double {
            depth += 1
            defer { depth -= 1 }
            guard depth <= 32 else { throw MathError.tooComplex }
            if take("+") { return try unary() }
            if take("-") { return try -unary() }
            var v = try atom()
            while take("%") { v /= 100 }
            if take("^") { v = pow(v, try unary()) }
            return v
        }
        mutating func atom() throws -> Double {
            if take("(") {
                let value = try sum(); guard take(")") else { throw MathError.invalid }; return value
            }
            if i < chars.count, chars[i].isLetter {
                let start = i
                while i < chars.count, chars[i].isLetter { i += 1 }
                let name = String(chars[start..<i])
                if name == "pi" { return .pi }
                if name == "e" { return exp(1) }
                // √144 and sqrt(144) are both accepted.
                let bracket = take("(")
                let value = try (bracket ? sum() : unary())
                if bracket && !take(")") { throw MathError.invalid }
                switch name {
                case "sqrt": return sqrt(value)
                case "sin": return sin(value)
                case "cos": return cos(value)
                case "tan": return tan(value)
                case "abs": return abs(value)
                case "ln": return log(value)
                case "log": return log10(value)
                case "exp": return exp(value)
                case "round": return round(value)
                case "floor": return floor(value)
                case "ceil": return ceil(value)
                default: throw MathError.invalid
                }
            }
            let start = i
            while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
            if i < chars.count && chars[i] == "e" {
                i += 1
                if i < chars.count && (chars[i] == "+" || chars[i] == "-") { i += 1 }
                while i < chars.count && chars[i].isNumber { i += 1 }
            }
            guard i > start, let number = Double(String(chars[start..<i])) else { throw MathError.invalid }
            return number
        }
    }
}
