import Foundation

public enum CommonSearchFolder: String, CaseIterable, Identifiable, Sendable {
    case downloads, desktop, movies, music, pictures, documents
    public var id: String { rawValue }
    public var title: String {
        switch self { case .downloads: return "下載"; case .desktop: return "桌面"; case .movies: return "影片"; case .music: return "音樂"; case .pictures: return "圖片"; case .documents: return "文件" }
    }
    public var url: URL {
        let directory: FileManager.SearchPathDirectory
        switch self { case .downloads: directory = .downloadsDirectory; case .desktop: directory = .desktopDirectory; case .movies: directory = .moviesDirectory; case .music: directory = .musicDirectory; case .pictures: directory = .picturesDirectory; case .documents: directory = .documentDirectory }
        return FileManager.default.urls(for: directory, in: .userDomainMask)[0]
    }
    /// Pure path construction; no protected folders are probed before the user selects them.
    public static var defaultURLs: [URL] { allCases.map(\.url) }
}
