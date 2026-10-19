import SwiftUI
import Translation
import NaturalLanguage
import HanSearchCore

/// Automatic translation never requests a download. Setup lives in a normal separate window.
@available(macOS 15.0, *)
struct TranslationBridge: View {
    @ObservedObject var store: SearchStore
    @State private var configuration: TranslationSession.Configuration?
    @State private var text = ""
    @State private var sourceID = ""
    @State private var token = UUID()
    private let target = Locale.Language(identifier: "zh-Hant")
    private var requestID: String { store.query + "|" + store.mode.rawValue + "|" + String(store.translationEnabled) }
    var body: some View {
        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            .task(id: requestID) { await translateAutomatic() }
            .translationTask(configuration) { session in
                let capturedText = text, capturedToken = token, source = sourceID
                do {
                    let result = try await session.translate(capturedText)
                    guard capturedToken == token, currentQuery == capturedText else { return }
                    publish(result.targetText)
                } catch {
                    guard capturedToken == token, currentQuery == capturedText else { return }
                    needsSetup(source)
                }
            }
    }
    private var currentQuery: String { store.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    @MainActor private func publish(_ translated: String) {
        guard store.translationEnabled else { return }
        let value = ChineseSearch.traditional(translated)
        store.setTranslation(QuickResult(id: "translation", title: value, subtitle: "繁體中文翻譯 · Apple 本機翻譯 · 選取後 ↵ 複製", symbol: "translate", action: .copy(value)))
    }
    @MainActor private func needsSetup(_ source: String) {
        store.setTranslation(QuickResult(id: "translation", title: "準備本機繁體中文翻譯", subtitle: "首次需準備語言 · 選取後 ↵ 開啟語言設定 · 下方照常搜尋", symbol: "translate", action: .prepareTranslation(source)))
    }
    @MainActor private func translateAutomatic() async {
        token = UUID(); configuration = nil; store.setTranslation(nil)
        let query = currentQuery
        guard store.translationEnabled, [.all, .apps, .names, .videos, .contents].contains(store.mode), query.count >= 2, query.count <= 200,
              query.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 2,
              !CurrencyQuery.isCurrencyQuery(query), TaskCommandParser.parse(query) == nil,
              !Calculator.looksLikeExpression(query), UnitConverter.convert(query) == nil,
              !query.contains("://"), !query.hasPrefix("define "), !query.hasPrefix("查 "),
              let language = NLLanguageRecognizer.dominantLanguage(for: query), language != .simplifiedChinese, language != .traditionalChinese else { return }
        do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
        let source = Locale.Language(identifier: language.rawValue)
        let status = await LocalTranslationSupport.availability().status(from: source, to: target)
        guard !Task.isCancelled, currentQuery == query else { return }
        switch status {
        case .unsupported: return
        case .supported: needsSetup(language.rawValue)
        case .installed:
            text = query; sourceID = language.rawValue; token = UUID()
            if #available(macOS 26.0, *) {
                let session = LocalTranslationSupport.session(source: source, target: target)
                do {
                    let result = try await session.translate(query)
                    guard !Task.isCancelled, currentQuery == query else { return }
                    publish(result.targetText)
                } catch {
                    guard !Task.isCancelled, currentQuery == query else { return }
                    needsSetup(language.rawValue)
                }
            } else {
                var next = LocalTranslationSupport.configuration(source: source, target: target)
                next.invalidate(); configuration = next
            }
        @unknown default: return
        }
    }
}

@available(macOS 15.0, *)
private enum LocalTranslationSupport {
    static func availability() -> LanguageAvailability {
        if #available(macOS 26.4, *) { return LanguageAvailability(preferredStrategy: .lowLatency) }
        return LanguageAvailability()
    }
    @available(macOS 26.0, *)
    static func session(source: Locale.Language, target: Locale.Language) -> TranslationSession {
        if #available(macOS 26.4, *) { return TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency) }
        return TranslationSession(installedSource: source, target: target)
    }
    static func configuration(source: Locale.Language, target: Locale.Language) -> TranslationSession.Configuration {
        if #available(macOS 26.4, *) { return TranslationSession.Configuration(source: source, target: target, preferredStrategy: .lowLatency) }
        return TranslationSession.Configuration(source: source, target: target)
    }
}

@available(macOS 15.0, *)
struct TranslationSetupView: View {
    @ObservedObject var store: SearchStore
    let source: String
    let query: String
    let close: () -> Void
    @State private var status = "正在檢查本機語言…"
    @State private var busy = false
    @State private var configuration: TranslationSession.Configuration?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("本機翻譯語言", systemImage: "translate").font(.title2)
            Text(status).font(.callout).textSelection(.enabled)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("開啟語言下載設定") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension?translation")!) }
                Button("檢查狀態") { Task { await check() } }.disabled(busy)
                Button("完成") { close() }
            }
        }.padding(24).frame(width: 520, height: 220)
        .task { await check() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await check() }
        }
        .translationTask(configuration) { session in
            do { let response = try await session.translate(query); success(response.targetText) }
            catch { status = "本機翻譯目前無法完成；請檢查語言下載狀態後重試。" }
            busy = false
        }
    }
    private func success(_ translated: String) {
        let result = ChineseSearch.traditional(translated)
        status = "語言已準備完成：\(result)。之後會在搜尋結果上方自動翻譯。"
        if store.query.trimmingCharacters(in: .whitespacesAndNewlines) == query, store.translationEnabled {
            store.setTranslation(QuickResult(id: "translation", title: result, subtitle: "繁體中文翻譯 · Apple 本機翻譯 · 選取後 ↵ 複製", symbol: "translate", action: .copy(result)))
        }
    }
    @MainActor private func check() async {
        guard !busy else { return }
        busy = true
        let from = Locale.Language(identifier: source), to = Locale.Language(identifier: "zh-Hant")
        let state = await LocalTranslationSupport.availability().status(from: from, to: to)
        guard state == .installed else {
            let name = Locale.current.localizedString(forLanguageCode: source) ?? source
            status = state == .unsupported ? "系統目前不支援這一組翻譯語言。" : "請按「開啟語言下載設定」，下載\(name)與繁體中文。完成後回到此視窗會自動檢查；下載只需一次，可跨 App 共用。"
            busy = false; return
        }
        if #available(macOS 26.0, *) {
            do { let response = try await LocalTranslationSupport.session(source: from, target: to).translate(query); success(response.targetText) }
            catch { status = "語言已安裝，但翻譯暫時無法完成。請稍後重試。" }
            busy = false
        } else {
            var next = LocalTranslationSupport.configuration(source: from, target: to)
            next.invalidate(); configuration = next
        }
    }
}
