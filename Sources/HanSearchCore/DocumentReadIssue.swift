import Foundation

public enum DocumentReadReason: String, CaseIterable, Sendable, Error, LocalizedError {
    case tooLarge, cloudOnly, textBudget, noText, locked, legacyNeedsSystemIndex, legacySpreadsheet, spreadsheetLimit, readFailed
    public var title: String {
        switch self {
        case .tooLarge: return "超過單檔 20 MB 上限"
        case .cloudOnly: return "雲端檔案尚未下載"
        case .textBudget: return "已達內文總量 32 MB 上限"
        case .noText: return "沒有可擷取的文字（空白或圖片）"
        case .locked: return "PDF 受密碼保護"
        case .legacyNeedsSystemIndex: return "舊版 PPT 請使用系統索引搜尋"
        case .legacySpreadsheet: return "舊版或二進位 Excel 請使用系統索引搜尋"
        case .spreadsheetLimit: return "Excel 結構或文字超過讀取上限"
        case .readFailed: return "格式、權限或讀取錯誤"
        }
    }
    public var errorDescription: String? { title }
}

public struct DocumentReadIssue: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let reason: DocumentReadReason
    public init(url: URL, reason: DocumentReadReason) { self.url = url; self.reason = reason }
}
