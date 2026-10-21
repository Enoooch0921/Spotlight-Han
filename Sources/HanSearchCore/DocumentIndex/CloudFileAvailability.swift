import Foundation

public enum CloudFileAvailability {
    public static func needsDownload(isUbiquitous: Bool, status: URLUbiquitousItemDownloadingStatus?) -> Bool {
        isUbiquitous && status != .current && status != .downloaded
    }
}
