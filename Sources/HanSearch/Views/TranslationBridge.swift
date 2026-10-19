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
    @State private var configuredRequest = ""
    private var target: Locale.Language { Locale.Language(identifier: store.translationTarget) }
    private var requestID: String { store.query + "|" + store.mode.rawValue + "|" + String(store.translationEnabled) + "|" + store.translationSource + "|" + store.translationTarget + "|" + (store.composerMode?.rawValue ?? "") }
    var body: some View {
        Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
            .task(id: requestID) { await translateAutomatic() }
            .translationTask(configuration) { session in
                let capturedText = text, capturedToken = token, source = sourceID, request = configuredRequest
                do {
                    let result = try await session.translate(capturedText)
                    guard !Task.isCancelled, capturedToken == token, request == requestID, currentQuery == capturedText else { return }
                    publish(result.targetText)
                } catch {
                    guard !Task.isCancelled, capturedToken == token, request == requestID, currentQuery == capturedText else { return }
                    needsSetup(source)
                }
            }
    }
    private var currentQuery: String { store.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    @MainActor private func publish(_ translated: String) {
        guard store.translationEnabled else { return }
        let value = store.translationTarget == "zh-Hant" ? ChineseSearch.traditional(translated) : translated
        let name = store.interfaceLanguage.locale.localizedString(forIdentifier: store.translationTarget) ?? store.translationTarget
        store.setTranslation(QuickResult(id: "translation", title: value, subtitle: "\(name)翻譯 · Apple 本機翻譯 · 選取後 ↵ 複製", symbol: "translate", action: .copy(value)))
    }
    @MainActor private func needsSetup(_ source: String) {
        store.setTranslation(QuickResult(id: "translation", title: "準備本機翻譯語言", subtitle: "首次需準備語言 · 選取後 ↵ 開啟語言設定 · 下方照常搜尋", symbol: "translate", action: .prepareTranslation(source)))
    }
    @MainActor private func translateAutomatic() async {
        token = UUID(); configuration = nil; store.setTranslation(nil)
        let query = currentQuery, request = requestID
        guard store.composerMode == nil, store.translationEnabled, [.all, .apps, .names, .videos, .contents].contains(store.mode), query.count >= 2, query.count <= 200,
              query.unicodeScalars.filter({ CharacterSet.letters.contains($0) }).count >= 2,
              !CurrencyQuery.isCurrencyQuery(query), TaskCommandParser.parse(query) == nil, SystemSettingsCatalog.results(query: query).isEmpty,
              !Calculator.looksLikeExpression(query), UnitConverter.convert(query) == nil,
              !query.contains("://"), !query.hasPrefix("define "), !query.hasPrefix("查 ") else { return }
        let language = store.translationSource == "auto" ? NLLanguageRecognizer.dominantLanguage(for: query) : NLLanguage(rawValue: store.translationSource)
        guard let language, Locale.Language(identifier: language.rawValue).languageCode != target.languageCode else { return }
        do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
        let source = Locale.Language(identifier: language.rawValue)
        let status = await LocalTranslationSupport.availability().status(from: source, to: target)
        guard !Task.isCancelled, request == requestID, currentQuery == query else { return }
        switch status {
        case .unsupported: return
        case .supported: needsSetup(language.rawValue)
        case .installed:
            text = query; sourceID = language.rawValue; token = UUID(); configuredRequest = request
            if #available(macOS 26.0, *) {
                let session = LocalTranslationSupport.session(source: source, target: target)
                do {
                    let result = try await session.translate(query)
                    guard !Task.isCancelled, request == requestID, currentQuery == query else { return }
                    publish(result.targetText)
                } catch {
                    guard !Task.isCancelled, request == requestID, currentQuery == query else { return }
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
    @State private var monitoring = true
    @State private var installed = false
    @State private var checkedAt: Date?
    @State private var startedAt = Date()
    @State private var closed = false
    @State private var generation = UUID()
    @State private var configurationPair = ""
    @State private var configurationGeneration = UUID()
    private var pair: String { sourceID + "|" + store.translationTarget }
    private var sourceID: String { store.translationSource == "auto" ? source : store.translationSource }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L.text("本機翻譯語言"), systemImage: "translate").font(.title2)
            TranslationLanguageSettingsView(store: store)
            Text(L.text(status)).font(.callout).textSelection(.enabled)
            if monitoring && !installed {
                ProgressView().progressViewStyle(.linear).controlSize(.small)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(L.text("等待語言準備完成 · 已等待 \(Int(context.date.timeIntervalSince(startedAt))) 秒"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let checkedAt {
                Text(L.text("上次檢查：\(checkedAt.formatted(date: .omitted, time: .standard)) · 系統未提供下載百分比"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(L.text("查看系統語言下載")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension?translation")!) }
                Button(L.text("檢查狀態")) { Task { await check() } }.disabled(busy)
                Button(L.text("完成")) { monitoring = false; closed = true; close() }
            }
        }.padding(24).frame(width: 560, height: 460)
        .environment(\.locale, store.interfaceLanguage.locale)
        .task(id: pair) {
            guard !closed else { return }
            startedAt = Date(); installed = false; monitoring = true; busy = false
            generation = UUID(); configuration = nil
            while !Task.isCancelled && monitoring && !installed {
                await check()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await check() }
        }
        .onDisappear { monitoring = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if (notification.object as? NSWindow)?.title == "Spotlight Han · 本機翻譯語言" { closed = true; monitoring = false }
        }
        .translationTask(configuration) { session in
            let capturedPair = configurationPair, capturedGeneration = configurationGeneration
            do {
                let response = try await session.translate(query)
                guard !Task.isCancelled, !closed, capturedPair == pair, capturedGeneration == generation else { return }
                success(response.targetText)
            } catch {
                guard !Task.isCancelled, !closed, capturedPair == pair, capturedGeneration == generation else { return }
                status = "本機翻譯目前無法完成；請檢查語言下載狀態後重試。"
            }
            busy = false
        }
    }
    private func success(_ translated: String) {
        let result = store.translationTarget == "zh-Hant" ? ChineseSearch.traditional(translated) : translated
        status = "語言已準備完成：\(result)。之後會在搜尋結果上方自動翻譯。"
        if store.query.trimmingCharacters(in: .whitespacesAndNewlines) == query, store.translationEnabled {
            store.setTranslation(QuickResult(id: "translation", title: result, subtitle: "Apple 本機翻譯 · 選取後 ↵ 複製", symbol: "translate", action: .copy(result)))
        }
    }
    @MainActor private func check() async {
        guard !busy, !closed else { return }
        busy = true
        let capturedPair = pair, capturedGeneration = generation
        let from = Locale.Language(identifier: sourceID), to = Locale.Language(identifier: store.translationTarget)
        let state = await LocalTranslationSupport.availability().status(from: from, to: to)
        guard !Task.isCancelled, !closed, pair == capturedPair, generation == capturedGeneration else { return }
        checkedAt = Date(); installed = state == .installed
        guard state == .installed else {
            let name = store.interfaceLanguage.locale.localizedString(forIdentifier: sourceID) ?? sourceID
            let targetName = store.interfaceLanguage.locale.localizedString(forIdentifier: store.translationTarget) ?? store.translationTarget
            monitoring = state != .unsupported
            status = state == .unsupported ? "系統目前不支援這一組翻譯語言。" : "語言尚未準備完成。請到系統下載\(name)與\(targetName)。此視窗每 3 秒檢查是否已安裝；系統未提供下載百分比。"
            busy = false; return
        }
        if query.isEmpty {
            status = "所選語言已安裝，可以開始翻譯。"
            busy = false; return
        }
        if #available(macOS 26.0, *) {
            do {
                let response = try await LocalTranslationSupport.session(source: from, target: to).translate(query)
                guard !Task.isCancelled, !closed, pair == capturedPair, generation == capturedGeneration else { return }
                success(response.targetText)
            } catch {
                guard !Task.isCancelled, !closed, pair == capturedPair, generation == capturedGeneration else { return }
                status = "語言已安裝，但翻譯暫時無法完成。請稍後重試。"
            }
            busy = false
        } else {
            configurationPair = capturedPair; configurationGeneration = capturedGeneration
            var next = LocalTranslationSupport.configuration(source: from, target: to)
            next.invalidate(); configuration = next
        }
    }
}
