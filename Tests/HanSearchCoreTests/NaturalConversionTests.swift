import Foundation
import HanSearchCore

extension ChineseSearchTests {
    func testNaturalConversions() {
        func expect(_ query: String, _ expected: Double, suffix: String, scale: TemperatureScale = .celsius, line: UInt = #line) {
            guard let answer = UnitConverter.convert(query, defaultTemperatureScale: scale),
                  let value = Double(answer.split(separator: " ").first ?? "") else {
                preconditionFailure("Rejected conversion at \(line): \(query)")
            }
            precondition(abs(value - expected) < max(1, abs(expected)) * 1e-10 && answer.hasSuffix(" " + suffix), "Wrong conversion at \(line): \(query) -> \(answer)")
        }
        for query in ["3公斤換成磅", "3 公斤 換成 磅", "3公斤转磅", "3kg=磅", "3kg to lb", "3kgtolb", "3kg lb", "請幫我把3公斤換成磅", "请问3公斤等于几磅？"] {
            let suffix = query.contains("lb") ? "lb" : "磅"
            expect(query, 3 / 0.45359237, suffix: suffix)
        }
        for query in ["5公里多少公尺", "5公里是多少公尺", "5公里有多少公尺", "5公里有幾公尺", "5公里換算成公尺", "５公里＝公尺"] { expect(query, 5000, suffix: "公尺") }
        expect("10cmininch", 10 / 2.54, suffix: "inch")
        expect("1,000公克到公斤", 1, suffix: "公斤")
        expect(".5公斤=公克", 500, suffix: "公克")
        expect("1 GiB to MiB", 1024, suffix: "MiB")
        expect("1TB=GB", 1000, suffix: "GB")
        for query in ["37攝氏度", "37摄氏度", "37攝氏", "37°C", "37℃", "37c", "攝氏37度", "摄氏37度", "３７攝氏度"] { expect(query, 98.6, suffix: "°F") }
        for query in ["98.6華氏度", "98.6华氏度", "98.6°F", "98.6℉", "華氏98.6度", "fahrenheit98.6"] { expect(query, 37, suffix: "°C") }
        expect("37度", 98.6, suffix: "°F", scale: .celsius)
        expect("37度", 25.0/9.0, suffix: "°C", scale: .fahrenheit)
        expect("37°", 98.6, suffix: "°F")
        expect("37度轉華氏度", 98.6, suffix: "華氏度", scale: .celsius)
        expect("37攝氏度", 98.6, suffix: "°F", scale: .fahrenheit)
        expect("32°F=°C", 0, suffix: "°C")
        expect("0攝氏度換成華氏度", 32, suffix: "華氏度")
        expect("−40攝氏度", -40, suffix: "°F")
        expect("-459.67°F=K", 0, suffix: "K")
        expect("273.15K=°C", 0, suffix: "°C")
        for query in ["37度報告", "37度.txt", "37°C.pdf", "3kg lb.pdf", "3kglb", "單位換算教學", "1kg to km", "3公斤換成磅 extra", "3公斤5磅", "37度室內角度", "5度角", "3000tb", "3000tb=rmb", "200 USD to TWD", "nan°C", "inf°F", "-300°C", "-500°F", "-1K=°C", "37K", "3公斤", "1,2公斤=磅"] {
            precondition(UnitConverter.convert(query) == nil, "Unexpected conversion: \(query)")
        }
        precondition(TemperaturePreference.system.resolved(systemUnit: .fahrenheit) == .fahrenheit)
        precondition(TemperaturePreference.system.resolved(systemUnit: .celsius) == .celsius)
        precondition(TemperaturePreference.celsius.resolved(systemUnit: .fahrenheit) == .celsius)
        precondition(TemperaturePreference.fahrenheit.resolved(systemUnit: .celsius) == .fahrenheit)
        let automatic = QuickProvider.results(query: "37度", defaultTemperatureScale: .celsius).first { $0.id == "quick:temperature" }
        precondition(automatic?.title == "98.6 °F" && automatic?.subtitle.contains("37 °C") == true && automatic?.action == .copy("98.6 °F"))
        precondition(QuickProvider.results(query: "37度", defaultTemperatureScale: .fahrenheit).first { $0.id == "quick:temperature" }?.subtitle.contains("37 °F") == true)
        precondition(QuickProvider.results(query: "3公斤換成磅").contains { $0.id == "quick:conversion" })
        precondition(!QuickProvider.results(query: "3000tb").contains { $0.id == "quick:conversion" || $0.id == "quick:temperature" })
        precondition(CurrencyQuery.requests("3000tb", defaultTargets: ["CNY"]).first?.source == "TWD")
        print("PASS: space-free Chinese/English conversion triggers, temperature text/symbols, default/explicit scales, numeric validation, query/file guards, copy actions and currency separation")
    }
}
