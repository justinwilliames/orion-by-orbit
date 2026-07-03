import Foundation

/// Storage + survey-trigger logic for `BusinessContext`.
///
/// Lives in its own file so the BusinessContext feature surface can
/// move (or be removed) without churning the core AppSettings file.
extension AppSettings {

    static let businessContextKey                = "businessContext"
    static let businessContextLastShownVersionKey = "businessContextLastShownVersion"

    /// JSON-encoded BusinessContext, or nil if the user has never
    /// completed the survey (or has cleared their saved context).
    static var businessContext: BusinessContext? {
        get {
            guard let data = UserDefaults.standard.data(forKey: businessContextKey),
                  let decoded = try? JSONDecoder().decode(BusinessContext.self, from: data),
                  decoded.isComplete else {
                return nil
            }
            return decoded
        }
        set {
            if let newValue, newValue.isComplete,
               let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: businessContextKey)
            } else {
                UserDefaults.standard.removeObject(forKey: businessContextKey)
            }
        }
    }

    /// Current short version string from Info.plist. Used as the key
    /// for "have we already prompted the user this version?". Empty
    /// string fallback means we won't re-prompt across launches if the
    /// version can't be read — better than nagging on every open.
    private static var currentAppShortVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }

    /// Show the business-context prompt card?
    /// True only when (a) no context is saved AND (b) we haven't yet
    /// shown the prompt for this app version. After the user submits
    /// or skips, we mark this version as "shown" so we don't pester
    /// until they update the app.
    static var shouldPromptForBusinessContext: Bool {
        guard businessContext == nil else { return false }
        let lastShown = UserDefaults.standard.string(forKey: businessContextLastShownVersionKey) ?? ""
        return lastShown != currentAppShortVersion
    }

    /// Stamp the current app version as "we already prompted". Called
    /// on submit and on skip. Idempotent.
    static func markBusinessContextPromptShown() {
        UserDefaults.standard.set(currentAppShortVersion, forKey: businessContextLastShownVersionKey)
    }

    /// Clear all business-context state. Used by the global reset
    /// path so the user can rehearse the first-launch flow.
    static func clearBusinessContextState() {
        UserDefaults.standard.removeObject(forKey: businessContextKey)
        UserDefaults.standard.removeObject(forKey: businessContextLastShownVersionKey)
    }
}

extension Notification.Name {
    /// Fired when the saved business context changes (saved, edited,
    /// or cleared). Welcome panel listens to refresh the prompt card.
    static let liLJustinBusinessContextDidChange = Notification.Name("OrionBusinessContextDidChange")

    /// Request that the Settings window route to a specific pane on
    /// next open (or immediately, if already visible). Object is the
    /// `SettingsPane.rawValue` to switch to.
    static let liLJustinOpenSettingsPane = Notification.Name("OrionOpenSettingsPane")
}
