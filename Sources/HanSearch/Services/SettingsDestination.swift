import Foundation

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, search, files, sources, tools, about
    var id: Self { self }
    var title: String {
        switch self {
        case .general: return "一般"
        case .search: return "搜尋與快捷鍵"
        case .files: return "檔案與索引"
        case .sources: return "資料來源"
        case .tools: return "翻譯與工具"
        case .about: return "更新與關於"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .search: return "magnifyingglass"
        case .files: return "folder"
        case .sources: return "square.stack.3d.up"
        case .tools: return "character.bubble"
        case .about: return "info.circle"
        }
    }
}

