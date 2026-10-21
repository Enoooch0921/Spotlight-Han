import SwiftUI

private enum FileSettingsTab: String, CaseIterable, Identifiable {
    case overview = "概覽", scopes = "搜尋範圍", background = "背景辨識", advanced = "進階"
    var id: String { rawValue }
}

struct FileSearchSettingsView: View {
    @ObservedObject var store: SearchStore
    @State private var tab: FileSettingsTab = .overview
    var body: some View {
        VStack(spacing: 0) {
            Picker(L.text("檔案與索引設定分類"), selection: $tab) {
                ForEach(FileSettingsTab.allCases) { item in Text(L.text(item.rawValue)).tag(item) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("file-index-settings-tabs")
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
            Group {
                switch tab {
                case .overview: FileIndexOverviewView(store: store, editScopes: { tab = .scopes }, showDetails: { tab = .advanced })
                case .scopes: FileIndexScopesView(store: store)
                case .background: OCRIndexStatusView(store: store)
                case .advanced: DocumentIndexSettingsView(store: store)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
