import Foundation

/// Explicit vendor / product identifiers supplement the broad App Store categories.
/// Matching is local; this never sends an installed-app list to a server.
public enum ApplicationSuggestion: String, CaseIterable, Identifiable, Sendable {
    case waves, izotope, production, office, browsers, communication, playback, design, cloud
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .waves: return "Waves"
        case .izotope: return "iZotope"
        case .production: return "影音製作"
        case .office: return "Microsoft Office"
        case .browsers: return "瀏覽器"
        case .communication: return "通訊與會議"
        case .playback: return "影音播放"
        case .design: return "設計與截圖"
        case .cloud: return "雲端與遠端"
        }
    }
    public var symbol: String {
        switch self {
        case .waves: return "waveform"
        case .izotope: return "slider.horizontal.3"
        case .production: return "film"
        case .office: return "doc.text"
        case .browsers: return "globe"
        case .communication: return "bubble.left.and.bubble.right"
        case .playback: return "play.rectangle"
        case .design: return "paintbrush"
        case .cloud: return "cloud"
        }
    }
    public func matches(_ app: InstalledApplication) -> Bool {
        let id = app.bundleID?.lowercased() ?? ""
        switch self {
        case .waves:
            return id.hasPrefix("com.wavesaudio.") || id.hasPrefix("com.waves.") || app.url.pathComponents.contains("Waves")
        case .izotope: return id.hasPrefix("com.izotope.")
        case .production:
            return ["com.apple.finalcutapp", "com.apple.logic10", "com.apple.motionapp", "com.apple.compressor", "com.apple.mainstage3", "com.rationalacoustics.smaart", "com.lemon.lvpro", "com.lemon.lvoverseas", "com.obsproject.obs-studio", "org.latenitefilms.commandpost", "com.arobas-music.guitarpro8", "org.devcore.mixingstation.pc", "jp.co.yamaha.pa.tfeditor", "com.musictribe.wingedit", "app.freeshow", "com.worshipextreme.we4", "com.fxfactory.fxfactory", "com.motionvfx.minstaller"].contains(id)
                || id.hasPrefix("com.blackmagic-design.") || id.hasPrefix("com.blackmagicdesign.")
        case .office:
            return ["com.microsoft.word", "com.microsoft.excel", "com.microsoft.powerpoint", "com.microsoft.outlook", "com.microsoft.onenote.mac"].contains(id)
        case .browsers:
            return ["com.apple.safari", "com.google.chrome", "company.thebrowser.browser", "company.thebrowser.dia", "com.microsoft.edgemac", "org.mozilla.firefox", "com.brave.browser"].contains(id)
        case .communication:
            return ["jp.naver.line.mac", "com.tencent.xinwechat", "com.tencent.meeting", "us.zoom.xos", "com.tinyspeck.slackmacgap", "com.microsoft.teams2", "com.apple.mail", "com.apple.facetime", "com.apple.mobilesms", "com.apple.mobilephone"].contains(id)
        case .playback:
            return ["com.colliderli.iina", "com.movist.movistpro", "com.spotify.client", "com.apple.music", "com.apple.tv", "com.apple.podcasts", "com.apple.quicktimeplayerx", "org.videolan.vlc"].contains(id)
        case .design:
            return ["cc.ffitch.shottr", "com.apple.photos", "com.apple.generativeplaygroundapp", "com.apple.screenshot.launcher", "com.figma.desktop", "com.bohemiancoding.sketch3", "com.pixelmatorteam.pixelmator.x"].contains(id)
                || id.hasPrefix("com.adobe.") || id.hasPrefix("io.open-design.")
        case .cloud:
            return ["com.microsoft.onedrive", "com.synology.cloudstation", "com.dropbox.dropbox", "io.tailscale.ipn.macsys", "com.netease.uuremote", "com.google.drivefs", "com.apple.screensharing"].contains(id)
        }
    }
}
