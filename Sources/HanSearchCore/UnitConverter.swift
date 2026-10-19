import Foundation

public enum UnitConverter {
    private struct Unit { let group: Int; let factor: Double; let offset: Double }
    private static let units: [String: Unit] = {
        var result: [String: Unit] = [:]
        func add(_ names: String, _ group: Int, _ factor: Double, _ offset: Double = 0) {
            for name in names.split(separator: ",") { result[String(name)] = Unit(group: group, factor: factor, offset: offset) }
        }
        add("m,meter,meters,米,公尺", 0, 1); add("km,kilometer,kilometers,公里", 0, 1000)
        add("cm,公分,厘米", 0, 0.01); add("mm,毫米", 0, 0.001)
        add("in,inch,inches,吋,英寸", 0, 0.0254); add("ft,foot,feet,呎,英尺", 0, 0.3048)
        add("mi,mile,miles,英里", 0, 1609.344); add("yd,yard,yards,碼", 0, 0.9144)
        add("kg,公斤,千克", 1, 1); add("g,克,公克", 1, 0.001); add("mg,毫克", 1, 0.000001)
        add("lb,lbs,pound,pounds,磅", 1, 0.45359237); add("oz,ounce,ounces,盎司", 1, 0.028349523125)
        add("s,sec,second,seconds,秒", 2, 1); add("min,minute,minutes,分鐘,分", 2, 60)
        add("h,hr,hour,hours,小時", 2, 3600); add("day,days,天,日", 2, 86400)
        add("b,byte,bytes", 3, 1); add("kb", 3, 1000); add("mb", 3, 1e6); add("gb", 3, 1e9); add("tb", 3, 1e12)
        add("kib", 3, 1024); add("mib", 3, 1048576); add("gib", 3, 1073741824)
        add("c,°c,celsius,攝氏,℃", 4, 1); add("f,°f,fahrenheit,華氏,℉", 4, 5.0/9.0, -32.0 * 5.0/9.0)
        add("k,kelvin", 4, 1, -273.15)
        return result
    }()

    public static func convert(_ query: String) -> String? {
        let pattern = #"^\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))\s*(.+?)\s+(?:to|in|轉|到|換成)\s*(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
              let r1 = Range(match.range(at: 1), in: query), let r2 = Range(match.range(at: 2), in: query), let r3 = Range(match.range(at: 3), in: query),
              let value = Double(query[r1]) else { return nil }
        let from = String(query[r2]).lowercased(), to = String(query[r3]).lowercased()
        guard let source = units[from], let destination = units[to], source.group == destination.group else { return nil }
        let result = (value * source.factor + source.offset - destination.offset) / destination.factor
        guard result.isFinite else { return nil }
        return Calculator.format(result) + " " + query[r3]
    }
}
