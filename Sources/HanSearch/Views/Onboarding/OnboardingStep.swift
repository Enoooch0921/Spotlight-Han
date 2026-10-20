import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, shortcuts, files, sources, tools, ready
    var id: Self { self }
    var title: String {
        switch self {
        case .welcome: return "認識 Han"
        case .shortcuts: return "喚出與接續"
        case .files: return "檔案與內文"
        case .sources: return "你的資料來源"
        case .tools: return "日常工具"
        case .ready: return "準備就緒"
        }
    }
    var heading: String {
        switch self {
        case .welcome: return "記得什麼，就搜什麼。"
        case .shortcuts: return "一個快捷鍵，回到手邊的事。"
        case .files: return "先選範圍，再找得深入。"
        case .sources: return "讓常用資料，也進得了搜尋。"
        case .tools: return "少開幾個 App，多做一點事。"
        case .ready: return "你的 Han，準備好了。"
        }
    }
    var subtitle: String {
        switch self {
        case .welcome: return "繁簡、檔名、文件裡的字，都從同一個搜尋框開始。"
        case .shortcuts: return "選擇怎麼叫出 Han，以及下次開啟時要接續什麼。"
        case .files: return "檔名與內文是兩種索引；都只讀取你主動選取的資料夾。"
        case .sources: return "想搜尋哪一類，就連接哪一類。其餘可以留到需要時。"
        case .tools: return "先看幾個實際輸入方式，之後就能直接在搜尋框使用。"
        case .ready: return "已設定的範圍立即生效；還沒連接的功能，之後隨時補上。"
        }
    }
    var symbol: String {
        switch self {
        case .welcome: return "sparkle.magnifyingglass"
        case .shortcuts: return "keyboard"
        case .files: return "doc.text.magnifyingglass"
        case .sources: return "square.stack.3d.up"
        case .tools: return "sparkles"
        case .ready: return "checkmark.circle"
        }
    }
}
