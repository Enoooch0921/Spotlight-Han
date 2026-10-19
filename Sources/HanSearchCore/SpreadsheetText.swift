import Foundation

/// Extract displayed cell data without launching Excel, recalculating formulas or running macros.
public enum SpreadsheetText {
    public static func extract(_ url: URL, cancellation: ProcessCancellation? = nil) throws -> String {
        let listing = try ProcessRunner.run("/usr/bin/unzip", ["-Z1", url.path], timeout: 10, cancellation: cancellation, outputLimit: 1_000_000)
        let entries = String(decoding: listing, as: UTF8.self).split(separator: "\n").map(String.init)
        let parts = Set(entries)
        guard parts.count == entries.count else { throw DocumentReadReason.readFailed }
        var budget = 8_000_000
        func read(_ names: [String]) throws -> Data {
            guard budget > 0 else { throw DocumentReadReason.spreadsheetLimit }
            do {
                let data = try ProcessRunner.run("/usr/bin/unzip", ["-p", url.path] + names, timeout: 10, cancellation: cancellation, outputLimit: budget)
                budget -= data.count; return data
            } catch ProcessFailure.outputLimitExceeded { throw DocumentReadReason.spreadsheetLimit }
        }
        guard parts.contains("xl/workbook.xml"), parts.contains("xl/_rels/workbook.xml.rels") else { throw DocumentReadReason.readFailed }
        let book = WorkbookXML()
        try parse(read(["xl/workbook.xml"]), delegate: book, cancellation: cancellation)
        guard book.sheets.count <= 2000 else { throw DocumentReadReason.spreadsheetLimit }
        let relationships = WorkbookRelationships()
        try parse(read(["xl/_rels/workbook.xml.rels"]), delegate: relationships, cancellation: cancellation)
        var names: [String: String] = [:]
        for sheet in book.sheets {
            guard let target = relationships.targets[sheet.id] else { throw DocumentReadReason.readFailed }
            let decoded = target.removingPercentEncoding ?? target
            let path = ((decoded.hasPrefix("/") ? String(decoded.dropFirst()) : "xl/" + decoded) as NSString).standardizingPath
            if path.hasPrefix("xl/chartsheets/") { continue }
            guard path.range(of: #"^xl/worksheets/[^/]+\.xml$"#, options: .regularExpression) != nil, parts.contains(path), names[path] == nil else { throw DocumentReadReason.readFailed }
            names[path] = sheet.name
        }
        guard !names.isEmpty else { throw DocumentReadReason.noText }
        let strings = SharedStringsXML()
        if parts.contains("xl/sharedStrings.xml") { try parse(read(["xl/sharedStrings.xml"]), delegate: strings, cancellation: cancellation) }
        // Keep archive order for both the part list and concatenated worksheet output.
        let worksheets = entries.filter { names[$0] != nil }
        guard worksheets.count == names.count else { throw DocumentReadReason.readFailed }
        let cells = WorksheetXML(names: worksheets.compactMap { names[$0] }, strings: strings.values, cancellation: cancellation)
        try parse(read(worksheets), delegate: cells, cancellation: cancellation)
        guard !cells.invalidReference else { throw DocumentReadReason.readFailed }
        guard !cells.overLimit else { throw DocumentReadReason.spreadsheetLimit }
        guard !cells.text.isEmpty else { throw DocumentReadReason.noText }
        return cells.text
    }
    private static func parse(_ data: Data, delegate: XMLParserDelegate, cancellation: ProcessCancellation?) throws {
        if cancellation?.isCancelled == true { throw CancellationError() }
        guard let xml = String(data: data, encoding: .utf8), xml.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil, xml.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { throw DocumentReadReason.readFailed }
        let body = xml.replacingOccurrences(of: #"<\?xml[^?]*\?>"#, with: "", options: .regularExpression).replacingOccurrences(of: "\u{feff}", with: "")
        let parser = XMLParser(data: Data(("<han-root>" + body + "</han-root>").utf8))
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        let success = parser.parse()
        if cancellation?.isCancelled == true { throw CancellationError() }
        if let cells = delegate as? WorksheetXML, cells.overLimit { throw DocumentReadReason.spreadsheetLimit }
        guard success else { throw DocumentReadReason.readFailed }
    }
}

private final class WorkbookXML: NSObject, XMLParserDelegate {
    var sheets: [(id: String, name: String)] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "sheet", let name = attributes["name"], let id = attributes["r:id"] ?? attributes["id"] ?? attributes.first(where: { $0.key.hasSuffix(":id") })?.value { sheets.append((id, name)) }
    }
}
private final class WorkbookRelationships: NSObject, XMLParserDelegate {
    var targets: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "Relationship", attributes["TargetMode"]?.lowercased() != "external", let id = attributes["Id"], let target = attributes["Target"] { targets[id] = target }
    }
}
private final class SharedStringsXML: NSObject, XMLParserDelegate {
    var values: [String] = []
    private var buffer = "", reading = false, phonetic = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "si" { buffer = "" }
        if elementName == "rPh" { phonetic = true }
        if elementName == "t" { reading = !phonetic }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if reading { buffer += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if reading { buffer += String(decoding: CDATABlock, as: UTF8.self) } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "si" { values.append(buffer) }
        if elementName == "rPh" { phonetic = false }
        if elementName == "t" { reading = false }
    }
}
private final class WorksheetXML: NSObject, XMLParserDelegate {
    let names: [String], strings: [String], cancellation: ProcessCancellation?
    var text = "", invalidReference = false, overLimit = false
    private var sheet = -1, address = "", type = "", buffer = "", reading = false, phonetic = false, bytes = 0
    init(names: [String], strings: [String], cancellation: ProcessCancellation?) { self.names = names; self.strings = strings; self.cancellation = cancellation }
    private func append(_ line: String, parser: XMLParser) {
        bytes += line.utf8.count
        guard bytes <= 8_000_000 else { overLimit = true; parser.abortParsing(); return }
        text += line
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if cancellation?.isCancelled == true { parser.abortParsing(); return }
        if elementName == "worksheet" { sheet += 1; if sheet < names.count { append("【" + names[sheet] + "】\n", parser: parser) } }
        if elementName == "c" { address = attributes["r"] ?? ""; type = attributes["t"] ?? ""; buffer = "" }
        if elementName == "rPh" { phonetic = true }
        if elementName == "v" || elementName == "t" { reading = !phonetic }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if reading { buffer += string } }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if reading { buffer += String(decoding: CDATABlock, as: UTF8.self) } }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "rPh" { phonetic = false }
        if elementName == "v" || elementName == "t" { reading = false }
        if elementName == "c", sheet >= 0, sheet < names.count, !buffer.isEmpty {
            var value = buffer
            if type == "s" {
                guard let index = Int(buffer.trimmingCharacters(in: .whitespacesAndNewlines)), strings.indices.contains(index) else { invalidReference = true; parser.abortParsing(); return }
                value = strings[index]
            } else if type == "b" { value = buffer == "1" ? "TRUE" : "FALSE" }
            for line in value.split(whereSeparator: \.isNewline) {
                append(names[sheet] + "!" + address + "　" + line + "\n", parser: parser)
                if overLimit { return }
            }
        }
    }
}
