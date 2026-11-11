import Foundation

/// Minimal seam over `NSUbiquitousKeyValueStore` so tests never touch the real
/// iCloud key-value store. Modelled on `SkipSyncSession`
/// (`SkippedReminderSyncService.swift:18-34`).
public protocol UbiquitousKeyValueStoring: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func synchronize() -> Bool
}

/// Free conformance: the three selectors match the framework's own signatures.
extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStoring {}
