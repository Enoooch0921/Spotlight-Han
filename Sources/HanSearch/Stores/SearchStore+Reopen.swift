import Foundation
import HanSearchCore

extension SearchStore {
    /// Time begins when the panel is dismissed. Repeated hide callbacks do not
    /// extend retention, and a visible search is never cleared by a timer.
    func launcherDidHide(now: Date = Date()) {
        guard launcherSessionOpen else { return }
        launcherSessionOpen = false; launcherLastDismissed = now
    }
    func prepareLauncherForOpening(now: Date = Date(), continuingFlow: Bool = false) {
        guard !launcherSessionOpen else { return }
        launcherSessionOpen = true
        // System authorization/translation returns and unconfirmed task drafts
        // continue their flow, even if the ordinary search retention expired.
        guard !continuingFlow, !actionInFlight, composerMode == nil,
              reopenBehavior.shouldReset(lastDismissed: launcherLastDismissed, now: now, retention: reopenRetention) else { return }
        query = ""; details = nil; mode = defaultSearchMode
        appLibrary.isEditingCategory = false; appLibrary.isPreviewingSuggestions = false
        appLibrary.select(.all); appLibrary.selection = nil
        resetDocumentVerification(); search(); focusToken = UUID()
    }
}
