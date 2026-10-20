import Foundation

/// New installs see the guide once. Existing users keep their setup, with a replay entry.
@MainActor
final class OnboardingProgress {
    private let defaults: UserDefaults
    private let key = "onboardingFinished.v1"
    var hasFinished: Bool { defaults.bool(forKey: key) }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let existingKeys = ["shortcutBinding.v1", "documentIndexRoots.v1", "enabledSources.v1", "interfaceLanguage.v1", "searchReopenRetention.v1"]
        if defaults.object(forKey: key) == nil && existingKeys.contains(where: { defaults.object(forKey: $0) != nil }) {
            defaults.set(true, forKey: key)
        }
    }
    func finish() { defaults.set(true, forKey: key) }
}
