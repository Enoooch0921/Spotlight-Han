import Foundation
#if canImport(HanSearchCore)
import HanSearchCore
#endif

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, traditional = "zh-Hant", simplified = "zh-Hans", english = "en"
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return L.text("跟隨系統"); case .traditional: return "繁體中文"; case .simplified: return "简体中文"; case .english: return "English" }
    }
    var locale: Locale { Locale(identifier: self == .system ? Locale.preferredLanguages.first ?? "zh-Hant" : rawValue) }
}

/// Only apply to app-authored labels and status messages; filenames and personal text remain verbatim.
enum L {
    private static let english: [String: String] = {
        guard let url = Bundle.main.url(forResource: "Localization", withExtension: "json"),
              let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return result
    }()
    private static let templates: [(NSRegularExpression, String, String)] = english.keys.sorted {
        $0.replacingOccurrences(of: "%@", with: "").count > $1.replacingOccurrences(of: "%@", with: "").count
    }.compactMap { key in
        guard key.contains("%@") else { return nil }
        let pattern = "^" + key.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern).joined(separator: "(.+?)") + "$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        return (regex, key, english[key]!)
    }
    static var language: InterfaceLanguage { InterfaceLanguage(rawValue: UserDefaults.standard.string(forKey: "interfaceLanguage.v1") ?? "system") ?? .system }
    static func text(_ value: String) -> String {
        let identifier = language.locale.identifier.lowercased()
        let chinese = identifier.hasPrefix("zh")
        let simplified = chinese && (identifier.contains("hans") || identifier.contains("cn") || identifier.contains("sg"))
        if let result = english[value] { return chinese ? (simplified ? ChineseSearch.simplified(value) : value) : result }
        for (regex, key, translation) in templates {
            guard let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
            let translatedKey = chinese ? (simplified ? ChineseSearch.simplified(key) : key) : translation
            let pieces = translatedKey.components(separatedBy: "%@")
            guard pieces.count == match.numberOfRanges else { continue }
            var result = pieces[0]
            for index in 1..<pieces.count {
                if let range = Range(match.range(at: index), in: value) { result += String(value[range]) }
                result += pieces[index]
            }
            return result
        }
        return value
    }

    /// Translate the template before inserting user text, so filenames and names stay unchanged.
    static func format(_ key: String, _ values: String...) -> String {
        let pieces = text(key).components(separatedBy: "%@")
        guard pieces.count == values.count + 1 else { return key }
        return values.enumerated().reduce(pieces[0]) { $0 + $1.element + pieces[$1.offset + 1] }
    }
}
