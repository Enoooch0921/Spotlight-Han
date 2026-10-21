import Foundation

public enum DocumentReadReason: String, CaseIterable, Sendable, Error, LocalizedError {
    case tooLarge, cloudOnly, textBudget, noText, locked, legacyNeedsSystemIndex, legacySpreadsheet, spreadsheetLimit, readFailed, indexFileTextLimit, indexWorkLimit
    case ocrDeferred, ocrPending, ocrDisabled, ocrUnavailable, ocrFailed, ocrTimedOut, ocrFileTooLarge
    public var title: String {
        switch self {
        case .ocrDeferred: return "OCR 背景等待，已完成部分可搜尋"
        case .ocrPending: return "OCR 分批辨識中，已完成部分可搜尋"
        case .ocrDisabled: return "圖片或掃描頁需要開啟 OCR"
        case .ocrUnavailable: return "系統尚未提供所需的繁簡中文 OCR"
        case .ocrFailed: return "OCR 辨識未完成"
        case .ocrTimedOut: return "單頁 OCR 辨識逾時"
        case .ocrFileTooLarge: return "圖片或 PDF 超過單檔 100 MB 上限"
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
        case .ocrDeferred: return "工作保護解除，且符合電源、閒置與溫度條件後自動接續，毋須重新授權。"
        case .ocrPending: return "背景會接續辨識；暫停後從已儲存的批次繼續。"
        case .ocrDisabled: return "在索引設定開啟 Apple Vision OCR，再更新索引。"
        case .ocrUnavailable: return "請檢查 macOS 更新後再試；其他文字文件仍可搜尋。"
        case .ocrFailed, .ocrTimedOut: return "可重新更新索引；若持續失敗，請確認圖片清晰、檔案可開啟，或拆分文件。"
        case .cloudOnly: return "先在 Finder 下載並保留在本機，再更新索引。"
        case .noText: return "圖片或掃描頁可開啟 Han OCR；若辨識後仍無文字，請確認畫面清晰、方向正確；空白頁沒有內文可索引。"
        case .locked: return "請先用密碼開啟 PDF，另存可讀取的副本，再更新索引。"
        case .legacyNeedsSystemIndex: return "可另存成 PPTX，或開啟 Spotlight 補充搜尋。"
        case .legacySpreadsheet: return "可另存成 XLSX，或開啟 Spotlight 補充搜尋。"
        case .tooLarge, .ocrFileTooLarge, .indexFileTextLimit, .spreadsheetLimit, .indexWorkLimit:
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
