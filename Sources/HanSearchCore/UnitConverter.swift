import Foundation

public enum UnitConverter {
    private struct Unit { let group: Int; let factor: Double; let offset: Double }
    private static let units: [String: Unit] = {
        var result: [String: Unit] = [:]
        func add(_ names: String, _ group: Int, _ factor: Double, _ offset: Double = 0) {
            for name in names.split(separator: ",") {
                for variant in ChineseSearch.variants(String(name)) {
                    result[key(variant)] = Unit(group: group, factor: factor, offset: offset)
                }
            }
        }
        add("m,meter,meters,米,公尺", 0, 1); add("km,kilometer,kilometers,公里", 0, 1000)
        add("cm,centimeter,centimeters,centimetre,centimetres,公分,厘米", 0, 0.01); add("mm,millimeter,millimeters,毫米,公釐", 0, 0.001)
        add("in,inch,inches,吋,英寸", 0, 0.0254); add("ft,foot,feet,呎,英尺", 0, 0.3048)
        add("mi,mile,miles,英里", 0, 1609.344); add("yd,yard,yards,碼", 0, 0.9144)
        add("kg,kilogram,kilograms,公斤,千克", 1, 1); add("g,gram,grams,克,公克", 1, 0.001); add("mg,milligram,milligrams,毫克", 1, 0.000001)
        add("lb,lbs,pound,pounds,磅", 1, 0.45359237); add("oz,ounce,ounces,盎司", 1, 0.028349523125)
        add("s,sec,secs,second,seconds,秒", 2, 1); add("min,mins,minute,minutes,分鐘,分", 2, 60)
        add("h,hr,hrs,hour,hours,小時", 2, 3600); add("day,days,天,日", 2, 86400)
        add("b,byte,bytes", 3, 1); add("kb", 3, 1000); add("mb", 3, 1e6); add("gb", 3, 1e9); add("tb", 3, 1e12)
        add("kib", 3, 1024); add("mib", 3, 1048576); add("gib", 3, 1073741824)
        add("c,°c,celsius,攝氏,攝氏度,℃", 4, 1); add("f,°f,fahrenheit,華氏,華氏度,℉", 4, 5.0/9.0, -32.0 * 5.0/9.0)
        add("k,kelvin,克耳文,開爾文", 4, 1, -273.15)
        return result
    }()

    public struct Result: Sendable {
        public let text: String
        public let source: String
        public let automaticTemperature: Bool
    }
    private static func key(_ value: String) -> String { value.precomposedStringWithCompatibilityMapping.lowercased() }
    private static let number = #"([+-]?(?:[0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?|\.[0-9]+))"#
    private static let unitPattern = units.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
    private static let explicit = try! NSRegularExpression(pattern:
        #"^\s*(?:請問|请问|請|请)?\s*(?:幫我|帮我)?\s*(?:把|將|将)?\s*(?:換算|换算)?\s*"# + number + #"\s*("# + unitPattern + #"|度|°)(?:(?:\s*(?:換算成|换算成|換算為|换算为|轉換成|转换成|轉換為|转换为|換成|换成|轉成|转成|換算|换算|轉換|转换|等於|等于|是多少|有多少|有幾|有几|多少|幾|几|換|换|轉|转|到|成|=|→|to|in)\s*(?:多少|幾|几)?)|\s+)\s*("# + unitPattern + #")\s*(?:嗎|吗)?[?？]?\s*$"#,
        options: .caseInsensitive)
    private static let bareTemperature = try! NSRegularExpression(pattern: #"^\s*"# + number + #"\s*("# + unitPattern + #"|度|°)\s*[?？]?\s*$"#, options: .caseInsensitive)
    private static let leadingTemperature = try! NSRegularExpression(pattern: #"^\s*(攝氏|摄氏|華氏|华氏|celsius|fahrenheit)\s*"# + number + #"\s*度?\s*[?？]?\s*$"#, options: .caseInsensitive)

    public static func convert(_ query: String, defaultTemperatureScale: TemperatureScale = .celsius) -> String? {
        result(query, defaultTemperatureScale: defaultTemperatureScale)?.text
    }
    public static func result(_ query: String, defaultTemperatureScale: TemperatureScale = .celsius) -> Result? {
        guard query.count <= 200 else { return nil }
        let input = query.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: "−", with: "-")
        func groups(_ pattern: NSRegularExpression) -> [String]? {
            guard let match = pattern.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else { return nil }
            return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: input).map { String(input[$0]) } }
        }
        func value(_ text: String) -> Double? {
            guard let number = Double(text.replacingOccurrences(of: ",", with: "")), number.isFinite else { return nil }
            return number
        }
        if let parts = groups(explicit), let amount = value(parts[0]) {
            let from = parts[1] == "度" || parts[1] == "°" ? defaultTemperatureScale.symbol : parts[1]
            if let text = converted(amount, from: from, to: parts[2]) {
                return Result(text: text, source: Calculator.format(amount) + " " + from, automaticTemperature: false)
            }
        }
        let amount: Double, source: Unit
        if let parts = groups(bareTemperature), let number = value(parts[0]) {
            amount = number
            if parts[1] == "度" || parts[1] == "°" { source = units[key(defaultTemperatureScale.symbol)]! }
            else if let unit = units[key(parts[1])] { source = unit }
            else { return nil }
        } else if let parts = groups(leadingTemperature), let number = value(parts[1]), let unit = units[key(parts[0])] {
            amount = number; source = unit
        } else { return nil }
        // Only Celsius/Fahrenheit get an automatic opposite target. Bare K and ordinary units stay searches.
        guard source.group == 4, source.offset != -273.15 else { return nil }
        let scale: TemperatureScale = source.factor == 1 ? .celsius : .fahrenheit
        guard let text = converted(amount, from: scale.symbol, to: scale.opposite.symbol) else { return nil }
        return Result(text: text, source: Calculator.format(amount) + " " + scale.symbol, automaticTemperature: true)
    }
    private static func converted(_ value: Double, from: String, to: String) -> String? {
        guard let source = units[key(from)], let destination = units[key(to)], source.group == destination.group else { return nil }
        if source.group == 4, value * source.factor + source.offset < -273.15 - 1e-9 { return nil }
        let result = (value * source.factor + source.offset - destination.offset) / destination.factor
        guard result.isFinite else { return nil }
        return Calculator.format(abs(result) < 1e-10 ? 0 : result) + " " + to
    }
}
