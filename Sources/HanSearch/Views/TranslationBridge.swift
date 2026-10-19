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
              CurrencyQuery.parse(query) == nil, TaskCommandParser.parse(query) == nil,
              !Calculator.looksLikeExpression(query), UnitConverter.convert(query) == nil,
              !query.contains("://"), !query.hasPrefix("define "), !query.hasPrefix("查 "),
              let language = NLLanguageRecognizer.dominantLanguage(for: query), language != .simplifiedChinese, language != .traditionalChinese else { return }
        do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
        let source = Locale.Language(identifier: language.rawValue)
        let status = await LanguageAvailability().status(from: source, to: target)
        guard !Task.isCancelled, currentQuery == query else { return }
        switch status {
        case .unsupported: return
        case .supported: needsSetup(language.rawValue)
        case .installed:
            text = query; sourceID = language.rawValue; token = UUID()
            if #available(macOS 26.0, *) {
                let session = TranslationSession(installedSource: source, target: target)
                do {
                    let result = try await session.translate(query)
                    guard !Task.isCancelled, currentQuery == query else { return }
                    publish(result.targetText)
                } catch {
                    guard !Task.isCancelled, currentQuery == query else { return }
                    needsSetup(language.rawValue)
                }
            } else {
                var next = TranslationSession.Configuration(source: source, target: target)
                next.invalidate(); configuration = next
            }
        @unknown default: return
        }
    }
}

@available(macOS 15.0, *)
struct TranslationSetupView: View {
    @ObservedObject var store: SearchStore
    let source: String
    let query: String
    let close: () -> Void
    @State private var status = "請在 Apple 系統視窗下載來源語言與繁體中文。下載後可供其他 App 共用。"
    @State private var busy = true
    @State private var configuration: TranslationSession.Configuration?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("本機翻譯語言", systemImage: "translate").font(.title2)
            Text(status).font(.callout).textSelection(.enabled)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("開啟系統語言設定") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension?translation")!) }
                Button("重試") { configure() }.disabled(busy)
                Button("完成") { close() }
            }
        }.padding(24).frame(width: 480, height: 210)
        .onAppear { configure() }
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                let response = try await session.translate(query)
                let result = ChineseSearch.traditional(response.targetText)
                status = "語言已準備完成：\(result)。之後會在搜尋結果上方自動翻譯。"
                if store.query.trimmingCharacters(in: .whitespacesAndNewlines) == query, store.translationEnabled {
                    store.setTranslation(QuickResult(id: "translation", title: result, subtitle: "繁體中文翻譯 · Apple 本機翻譯 · 選取後 ↵ 複製", symbol: "translate", action: .copy(result)))
                }
            } catch { status = "語言尚未準備完成：\(error.localizedDescription)。下載若仍在背景進行，完成後按重試即可。" }
            busy = false
        }
    }
    private func configure() {
        busy = true
        var next = configuration ?? TranslationSession.Configuration(source: Locale.Language(identifier: source), target: Locale.Language(identifier: "zh-Hant"))
        next.invalidate(); configuration = next
    }
}
