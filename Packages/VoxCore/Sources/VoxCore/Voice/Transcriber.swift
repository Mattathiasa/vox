import Foundation

/// Abstraction over speech-to-text so the push-to-talk backend can be swapped
/// (SFSpeechRecognizer vs. SpeechAnalyzer on macOS 26+).
///
/// AppState holds a `Transcriber` and never touches a recognizer directly, so
/// the two backends are interchangeable for testing and for the on-device vs.
/// cloud accuracy comparison (Phase 3 follow-up).
public protocol Transcriber: AnyObject {
    /// Live partial transcript while listening.
    var onPartial: ((String) -> Void)? { get set }
    /// Words to bias recognition toward (tool, project and app names).
    var contextualStrings: [String] { get set }
    var isListening: Bool { get }

    /// Asks for speech + microphone access if needed. Throws if either is refused.
    func ensurePermissions() async throws
    /// Begins listening. Throws if the recognizer is unavailable.
    func start() throws
    /// Stops listening and returns the best final transcript (waits up to a
    /// short grace period for the recognizer to finalize).
    func stop() async -> String
    /// Stops without producing a result (a tap, not a hold).
    func cancel()
}
