import Foundation
@testable import VoxCore

/// Minimal fake `Transcriber` for tests. Records lifecycle calls and returns a
/// canned final transcript from `stop()`. Lets AppState-style flows be tested
/// without the Speech framework.
class FakeTranscriber: Transcriber, @unchecked Sendable {
    enum Call: Equatable, Sendable {
        case ensurePermissions
        case start
        case stop
        case cancel
    }

    var permissionDenied: Bool = false
    private(set) var finalText: String = ""
    private(set) var lastError: Error?

    private var _calls: [Call] = []
    private let lock = NSRecursiveLock()

    var calls: [Call] { lock.withLock { _calls } }
    private(set) var isListening: Bool = false
    var onPartial: ((String) -> Void)?
    var contextualStrings: [String] = []

    init(finalText: String = "", permissionDenied: Bool = false) {
        self.finalText = finalText
        self.permissionDenied = permissionDenied
    }

    func ensurePermissions() async throws {
        lock.withLock { _calls.append(.ensurePermissions) }
        if permissionDenied { lastError = NSError(domain: "FakeTranscriber", code: 1, userInfo: [NSLocalizedDescriptionKey: "mic denied"]) }
        if let err = lastError { throw err }
    }

    func start() throws {
        lock.withLock { _calls.append(.start) }
        isListening = true
    }

    func stop() async -> String {
        lock.withLock { _calls.append(.stop) }
        isListening = false
        return finalText
    }

    func cancel() {
        lock.withLock { _calls.append(.cancel) }
        isListening = false
    }
}

/// A transcriber whose `stop()` suspends for `delay` first, to test timeout
/// behaviour in callers.
final class SlowFakeTranscriber: FakeTranscriber {
    let delay: UInt64
    init(delay: Double, finalText: String = "") {
        self.delay = UInt64(delay * 1_000_000_000)
        super.init(finalText: finalText)
    }
    override func stop() async -> String {
        try? await Task.sleep(nanoseconds: delay)
        return await super.stop()
    }
}
