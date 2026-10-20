import Foundation

public enum DocumentReadReason: String, CaseIterable, Sendable, Error, LocalizedError {
    case tooLarge, cloudOnly, textBudget, noText, locked, legacyNeedsSystemIndex, legacySpreadsheet, spreadsheetLimit, readFailed, indexFileTextLimit, indexWorkLimit
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
        case .indexWorkLimit: return "文件頁數或讀取時間超過 Han 索引上限"
        case .indexFileTextLimit: return "單份文件文字超過 Han 索引 8 MB 上限"
        }
    }
    public var errorDescription: String? { title }
    public var recoverySuggestion: String {
        switch self {
        case .cloudOnly: return "先在 Finder 下載並保留在本機，再更新索引。"
        case .noText: return "掃描或圖片文件需要先做 OCR；空白文件沒有內文可索引。"
        case .locked: return "請先用密碼開啟 PDF，另存可讀取的副本，再更新索引。"
        case .legacyNeedsSystemIndex: return "可另存成 PPTX，或開啟 Spotlight 補充搜尋。"
        case .legacySpreadsheet: return "可另存成 XLSX，或開啟 Spotlight 補充搜尋。"
        case .tooLarge, .indexFileTextLimit, .spreadsheetLimit, .indexWorkLimit:
            return "可拆分成較小文件或匯出文字副本，再更新索引。"
        case .textBudget: return "請縮小資料夾範圍，或改用 Han 持久文件索引。"
        case .readFailed: return "先確認原檔能正常開啟；若權限不足，重新選取資料夾；若檔案損壞，請修復或重新匯出。"
        }
    }
}

public struct DocumentReadIssue: Identifiable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let reason: DocumentReadReason
    public init(url: URL, reason: DocumentReadReason) { self.url = url; self.reason = reason }
}
