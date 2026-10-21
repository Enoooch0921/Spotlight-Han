import Foundation

public enum TemperatureScale: String, Sendable {
    case celsius, fahrenheit
    public var symbol: String { self == .celsius ? "°C" : "°F" }
    public var opposite: Self { self == .celsius ? .fahrenheit : .celsius }
}

public enum TemperaturePreference: String, CaseIterable, Sendable {
    case system, celsius, fahrenheit
    public var title: String {
        switch self {
        case .system: return "跟隨系統"
        case .celsius: return "攝氏（°C）"
        case .fahrenheit: return "華氏（°F）"
        }
    }
    public func resolved(systemUnit: UnitTemperature = UnitTemperature(forLocale: .autoupdatingCurrent)) -> TemperatureScale {
        switch self {
        case .celsius: return .celsius
        case .fahrenheit: return .fahrenheit
        case .system: return systemUnit == .fahrenheit ? .fahrenheit : .celsius
        }
    }
}
