import Foundation

/// Observable in-memory holder for the phone-pushed `isEntitled` flag.
///
/// Unlike the Show*State holders, this does NOT double-persist — the flag is
/// received fresh on every context push and has no local StoreKit surface on
/// the watch, so it only lives for the current process.
@MainActor
@Observable
public final class EntitlementState {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public private(set) var isEnabled: Bool = false

    public func apply(_ value: Bool) {
        isEnabled = value
    }
}
