import Foundation

/// Named constants for the Bool preference keys persisted in UserDefaults.
/// Production callers use these cases; tests may inject custom key strings.
public enum BoolPreferenceKey: String, CaseIterable, Sendable {
    /// "showDate" — fallback: true
    case showDate
    /// "showRecurrence" — fallback: true
    case showRecurrence
    /// "showAlarms" — fallback: true
    case showAlarms
    /// "showCompletionGlow" — fallback: true
    case showCompletionGlow
    /// "showCompletionMomentum" — fallback: true
    case showCompletionMomentum
    /// "showList" — fallback: false
    case showList
    /// "showUndatedReminders" — fallback: false
    case showUndatedReminders
    /// "enableActionButtons" — fallback: true. The WatchConnectivity wire key
    /// is intentionally the same string so the payload and the persisted
    /// preference cannot drift.
    case enableActionButtons
}
