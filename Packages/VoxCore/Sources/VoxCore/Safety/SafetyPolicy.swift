import Foundation

/// Decides which utterances need a spoken "yes" before Vox acts on them.
///
/// This is a speed bump, not a sandbox: the tools Vox drives (coding agents)
/// have their own permissions. The point is that a misheard sentence or a
/// video playing in the background can't push, delete or deploy on its own.
public struct SafetyPolicy: @unchecked Sendable {
    // NSRegularExpression is immutable and thread-safe once built, which is
    // why the @unchecked Sendable above is fine.
    private let patterns: [NSRegularExpression]

    public init(patterns: [String]) {
        self.patterns = patterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }

    public init(config: VoxConfig) {
        self.init(patterns: config.confirmPatterns)
    }

    /// The first pattern the text matches, or nil if it is safe to act on directly.
    public func matchedPattern(in text: String) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for regex in patterns where regex.firstMatch(in: text, options: [], range: range) != nil {
            return regex.pattern
        }
        return nil
    }

    public func needsConfirmation(_ text: String) -> Bool {
        matchedPattern(in: text) != nil
    }
}
