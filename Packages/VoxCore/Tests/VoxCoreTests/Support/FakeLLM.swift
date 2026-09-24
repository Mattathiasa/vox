import Foundation
@testable import VoxCore

/// Minimal fake LLM for tests. Returns a canned result.
final class FakeLLM: LLMFallback, @unchecked Sendable {
    enum Call: Equatable, Sendable {
        case plan(LLMRequest)
    }

    private let results: [LLMResult]
    private let throwError: Error?
    private var _calls: [Call] = []
    private var _index = 0
    private let lock = NSRecursiveLock()

    init(results: [LLMResult] = [], throwError: Error? = nil) {
        self.results = results
        self.throwError = throwError
    }

    var calls: [Call] {
        lock.withLock { _calls }
    }

    func plan(request: LLMRequest) async throws -> LLMResult {
        lock.withLock {
            _calls.append(.plan(request))
        }
        if let err = throwError { throw err }
        let idx = lock.withLock {
            defer { _index += 1 }
            return _index
        }
        return idx < results.count ? results[idx] : .feedback("not configured")
    }
}

enum LLMTestError: Error { case boom }

/// Fake LLM that takes a while, for timeout testing.
final class SlowFakeLLM: LLMFallback, @unchecked Sendable {
    let delay: UInt64
    let result: LLMResult
    init(delay: Double, result: LLMResult) {
        self.delay = UInt64(delay * 1_000_000_000)
        self.result = result
    }
    func plan(request: LLMRequest) async throws -> LLMResult {
        try await Task.sleep(nanoseconds: delay)
        return result
    }
}
