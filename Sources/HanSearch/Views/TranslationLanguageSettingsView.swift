import SwiftUI
import Translation
import NaturalLanguage

@available(macOS 15.0, *)
struct TranslationLanguageSettingsView: View {
    @ObservedObject var store: SearchStore
    @State private var languages: [(id: String, name: String)] = []
    private var options: [(id: String, name: String)] {
        var result = languages
        for id in [store.translationTarget, store.translationSource].filter({ $0 != "auto" }) where !result.contains(where: { $0.id == id }) {
            result.append((id, store.interfaceLanguage.locale.localizedString(forIdentifier: id) ?? id))
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L.text("來源語言"), selection: $store.translationSource) {
                Text(L.text("自動偵測")).tag("auto")
                ForEach(options, id: \.id) { language in Text(language.name).tag(language.id) }
            }
            Picker(L.text("目標語言"), selection: $store.translationTarget) {
                ForEach(options, id: \.id) { language in Text(language.name).tag(language.id) }
            }
            Text(L.text("翻譯選單列出系統支援的語言；實際翻譯仍需下載所選語言模型。"))
                .font(.caption).foregroundStyle(.secondary)
            Button(L.text("準備所選翻譯語言…")) {
                let detected = NLLanguageRecognizer.dominantLanguage(for: store.query)?.rawValue
                let fallback = store.translationTarget.hasPrefix("en") ? "zh-Hant" : "en"
                store.prepareTranslation?(store.translationSource == "auto" ? (detected ?? fallback) : store.translationSource)
            }
        }.task(id: store.interfaceLanguage.rawValue) {
            let supported = await LanguageAvailability().supportedLanguages
            var ids = Set(supported.map(\.minimalIdentifier))
            ids.insert(store.translationTarget)
            if store.translationSource != "auto" { ids.insert(store.translationSource) }
            languages = ids.map { (id: $0, name: store.interfaceLanguage.locale.localizedString(forIdentifier: $0) ?? $0) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
