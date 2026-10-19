import Foundation

public enum PresentationText {
    public static func extract(_ url: URL, cancellation: ProcessCancellation? = nil) throws -> String {
        // Read XML parts in memory; do not extract archives onto the filesystem or launch PowerPoint.
        let list = try ProcessRunner.run("/usr/bin/unzip", ["-Z1", url.path], timeout: 10, cancellation: cancellation, outputLimit: 1_000_000)
        let pattern = #"^ppt/(slides/slide[0-9]+|notesSlides/notesSlide[0-9]+|charts/chart[0-9]+|diagrams/data[0-9]+)\.xml$"#
        let parts = String(decoding: list, as: UTF8.self).split(separator: "\n").map(String.init)
            .filter { $0.range(of: pattern, options: .regularExpression) != nil }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !parts.isEmpty, parts.count <= 2000 else { throw ProcessFailure.failed("簡報沒有可讀取的文字頁面，或超過讀取上限。") }
        let data = try ProcessRunner.run("/usr/bin/unzip", ["-p", url.path] + parts, timeout: 10, cancellation: cancellation, outputLimit: 8_000_000)
        guard let xml = String(data: data, encoding: .utf8),
              xml.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              xml.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
            throw ProcessFailure.failed("簡報文字格式無法安全讀取。")
        }
        let body = xml.replacingOccurrences(of: #"<\?xml[^?]*\?>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{feff}", with: "")
        let parser = XMLParser(data: Data(("<han-root>" + body + "</han-root>").utf8))
        let delegate = SlideText()
        parser.delegate = delegate; parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw ProcessFailure.failed("簡報 XML 文字無法完整讀取。") }
        if cancellation?.isCancelled == true { throw CancellationError() }
        return delegate.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class SlideText: NSObject, XMLParserDelegate {
    var text = ""
    private var reading = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        reading = elementName == "t" || elementName == "v"
        if elementName == "br" { text += "\n" }
        if elementName == "tab" { text += "\t" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if reading { text += string } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" || elementName == "v" { reading = false }
        if elementName == "v" { text += "\n" }
        if ["p", "sld", "notes", "chartSpace", "dataModel"].contains(elementName) { text += "\n" }
    }
}
