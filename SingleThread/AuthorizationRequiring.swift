@preconcurrency import Speech

// MARK: - AuthorizationRequiring protocol

/// Test seam: abstracts `SFSpeechRecognizer.requestAuthorization`'s callback API
/// so tests can deliver the completion from an off-main (`Task.detached`) context
/// and reproduce the queue mismatch the runtime asserts on. The production impl
/// wraps the real framework call; a fake drives the off-main delivery.
@MainActor
protocol AuthorizationRequiring: AnyObject {
    func requestAuthorization(
        completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void)
}

/// Production impl: forwards to the real `SFSpeechRecognizer.requestAuthorization`.
@MainActor
final class SpeechAuthorizationRequiring: AuthorizationRequiring {
    func requestAuthorization(
        completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization { @Sendable status in
            completion(status)
        }
    }
}
