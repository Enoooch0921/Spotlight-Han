import Foundation
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Sources/HanSearch/Resources")
let data = try Data(contentsOf: resources.appendingPathComponent("Localization.json"))
let catalog = try JSONDecoder().decode([String: String].self, from: data)
func quote(_ value: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed, .withoutEscapingSlashes])
    let array = String(decoding: data, as: UTF8.self)
    return String(array.dropFirst().dropLast())
}
for language in ["zh-Hant", "zh-Hans", "en"] {
    let directory = resources.appendingPathComponent(language + ".lproj")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let lines = catalog.keys.sorted().map { key -> String in
        let value = language == "en" ? catalog[key]! : (language == "zh-Hans" ? key.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? key : key)
        return "\(quote(key)) = \(quote(value));"
    }.joined(separator: "\n") + "\n"
    try lines.write(to: directory.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
}
print("Generated 3 localizations, \(catalog.count) entries each")
