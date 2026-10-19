import Foundation

enum FileResultSort: String, CaseIterable {
    case relevance, createdNewest, createdOldest
    var title: String {
        switch self {
        case .relevance: return "相關度"
        case .createdNewest: return "建立日期：新到舊"
        case .createdOldest: return "建立日期：舊到新"
        }
    }
}
