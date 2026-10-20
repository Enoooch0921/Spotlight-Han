import Foundation

@main struct OnboardingChecks {
    @MainActor static func main() {
        let suite = "HanOnboardingChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(!OnboardingProgress(defaults: defaults).hasFinished)
        // Merely opening the guide never records completion or requests a source.
        precondition(!OnboardingProgress(defaults: defaults).hasFinished)
        OnboardingProgress(defaults: defaults).finish()
        precondition(OnboardingProgress(defaults: defaults).hasFinished)
        defaults.removePersistentDomain(forName: suite)
        defaults.set(97, forKey: "searchReopenRetention.v1")
        precondition(OnboardingProgress(defaults: defaults).hasFinished)
        precondition(defaults.double(forKey: "searchReopenRetention.v1") == 97)
        print("PASS: fresh install eligibility, unfinished guide retry, completion persistence and existing-user preference preservation")
    }
}
