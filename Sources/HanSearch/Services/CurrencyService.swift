import Foundation
import HanSearchCore

actor CurrencyService {
    static let shared = CurrencyService()
    private struct Rates: Codable, Sendable {
        let result: String
        let base_code: String
        let time_last_update_unix: Double
        let time_next_update_unix: Double
        let rates: [String: Double]
        var valid: Bool {
            result == "success" && base_code == "USD" && rates["USD"] == 1 && time_last_update_unix > 0 && time_last_update_unix <= Date().timeIntervalSince1970 + 300 && time_next_update_unix > time_last_update_unix
        }
    }
    private var cached: Rates?
    private var pending: Task<Rates, Error>?
    private var lastAttempt = Date.distantPast
    private let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("local.hansearch.mac/ExchangeRates-v1.json")
    private init() {
        if let data = try? Data(contentsOf: cacheURL), let rates = try? JSONDecoder().decode(Rates.self, from: data), rates.valid { cached = rates }
    }
    func results(for queries: [CurrencyQuery]) async -> [QuickResult] {
        guard !queries.isEmpty else { return [] }
        do {
            let data = try await load()
            let timestamp = Date(timeIntervalSince1970: data.time_last_update_unix).formatted(date: .abbreviated, time: .shortened)
            let stale = Date().timeIntervalSince1970 >= data.time_next_update_unix
            return queries.map { query in
                guard let conversion = query.converted(using: data.rates) else {
                    return QuickResult(id: "currency:" + query.target, title: query.target + " 暫無可用匯率", subtitle: "來源沒有這個貨幣的有效資料", symbol: "exclamationmark.circle", action: .details("此幣別目前沒有可用匯率。"))
                }
                let formatted = CurrencyQuery.money(conversion.amount, code: query.target)
                let subtitle = "1 \(query.source) ≈ \(String(format: "%.6g", conversion.rate)) \(query.target) · 資料 \(timestamp)" + (stale ? " · 過期快取" : "") + " · 每日更新 · 參考匯率"
                return QuickResult(id: "currency:" + query.target, title: "≈ " + formatted, subtitle: subtitle, symbol: "dollarsign.circle", action: .copy(formatted))
            }
        } catch {
            return [QuickResult(id: "currency:error", title: "目前無法取得匯率", subtitle: error.localizedDescription + " · 搜尋結果仍可使用", symbol: "exclamationmark.circle", action: .details(error.localizedDescription))]
        }
    }
    private func load() async throws -> Rates {
        let now = Date()
        if let cached, now.timeIntervalSince1970 < cached.time_next_update_unix { return cached }
        if let pending { return try await pending.value }
        // Public data updates daily. Coalesce requests and back off on offline/rate-limit failures.
        guard now.timeIntervalSince(lastAttempt) >= 60 else {
            if let cached, now.timeIntervalSince1970 - cached.time_last_update_unix < 7 * 86400 { return cached }
            throw ProcessFailure.failed("網路或匯率服務暫不可用，稍後再試。")
        }
        lastAttempt = now
        let task = Task<Rates, Error> {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            // Always fetch the same USD table: no amount, query text, or filenames leave the Mac.
            var request = URLRequest(url: URL(string: "https://open.er-api.com/v6/latest/USD")!)
            request.timeoutInterval = 10
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count < 128_000 else { throw ProcessFailure.failed("匯率服務暫不可用。") }
            let rates = try JSONDecoder().decode(Rates.self, from: data)
            guard rates.valid else { throw ProcessFailure.failed("匯率資料不完整，無法換算。") }
            return rates
        }
        pending = task
        defer { pending = nil }
        do {
            let rates = try await task.value
            cached = rates
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(rates) { try? data.write(to: cacheURL, options: .atomic) }
            return rates
        } catch {
            if let cached, now.timeIntervalSince1970 - cached.time_last_update_unix < 7 * 86400 { return cached }
            throw error
        }
    }
}
