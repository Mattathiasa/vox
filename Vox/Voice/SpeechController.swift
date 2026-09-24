import AVFoundation
import Speech
import VoxCore

/// Microphone loudness (0…1) shared between the audio thread and the HUD.
/// Audio taps write it; the HUD polls it ~20×/s.
final class AudioLevel: @unchecked Sendable {
    static let shared = AudioLevel()
    private let lock = NSLock()
    private var current: Float = 0

    var value: Float {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func update(_ buffer: AVAudioPCMBuffer) {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let rms = (sum / Float(count)).squareRoot()
        // -50 dB … 0 dB -> 0 … 1
        let db = 20 * log10(max(rms, 0.000_01))
        let level = max(0, min(1, (db + 50) / 50))
        lock.lock()
        current = current * 0.6 + level * 0.4
        lock.unlock()
    }

    func reset() {
        lock.lock(); current = 0; lock.unlock()
    }
}

enum VoiceError: Error, CustomStringConvertible {
    case recognizerUnavailable
    case speechDenied
    case microphoneDenied

    var description: String {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognition isn't available right now (check System Settings › Keyboard › Dictation language)."
        case .speechDenied:
            return "Speech recognition is off for Vox. Turn it on in System Settings › Privacy & Security › Speech Recognition."
        case .microphoneDenied:
            return "Microphone access is off for Vox. Turn it on in System Settings › Privacy & Security › Microphone."
        }
    }
}

/// Push-to-talk speech-to-text: `start()` while the key is down, `stop()` on
/// release returns the final transcript. On-device when the Mac supports it.
///
/// Phase 3 follow-up: this now conforms to `Transcriber`, so the SFSpeechRecognizer
/// backend can be swapped for a `SpeechAnalyzer` (macOS 26+) backend for comparison.
@MainActor
final class SpeechController: Transcriber {
    /// Live partial transcript while listening.
    var onPartial: ((String) -> Void)?
    /// Words to bias recognition toward (tool, project and app names).
    var contextualStrings: [String] = []

    private(set) var isListening = false
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var finalWaiter: CheckedContinuation<String, Never>?

    // MARK: Permissions

    /// Asks for speech + microphone access if needed. Throws if either is refused.
    /// Instance front for `Transcriber`; wraps the static implementation so the
    /// backend is selectable through the protocol.
    func ensurePermissions() async throws {
        try await Self.ensurePermissions()
    }

    nonisolated static func ensurePermissions() async throws {
        var speech = SFSpeechRecognizer.authorizationStatus()
        if speech == .notDetermined {
            speech = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        guard speech == .authorized else { throw VoiceError.speechDenied }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return }
            throw VoiceError.microphoneDenied
        default:
            throw VoiceError.microphoneDenied
        }
    }

    // MARK: Listening

    func start() throws {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else { throw VoiceError.recognizerUnavailable }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.addsPunctuation = false
        self.request = request
        latest = ""

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(request))
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler { [weak self] text, isFinal in
            Task { @MainActor in self?.receive(text: text, isFinal: isFinal) }
        })
        isListening = true
    }

    /// Stops listening and returns the best transcript (waits up to 1.5 s for
    /// the recognizer to finalize).
    func stop() async -> String {
        guard isListening else { return latest }
        stopAudio()
        request?.endAudio()

        let text = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            finalWaiter = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self?.resolveWaiter()
            }
        }
        task?.cancel()
        task = nil
        request = nil
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stops without producing a result (a tap, not a hold).
    func cancel() {
        guard isListening else { return }
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        latest = ""
        resolveWaiter()
    }

    // MARK: Private

    private func stopAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isListening = false
    }

    private func receive(text: String?, isFinal: Bool) {
        if let text {
            latest = text
            onPartial?(text)
        }
        if isFinal { resolveWaiter() }
    }

    private func resolveWaiter() {
        guard let waiter = finalWaiter else { return }
        finalWaiter = nil
        waiter.resume(returning: latest)
    }

    // Built outside the main actor: these closures run on audio/recognizer threads.
    nonisolated private static func makeTap(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            AudioLevel.shared.update(buffer)
        }
    }

    nonisolated private static func makeResultHandler(
        _ deliver: @escaping @Sendable (String?, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            deliver(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }
}

// MARK: - Spoken replies

/// Speaks short replies ("Notes isn't running", confirmation questions) so
/// voice commands work without looking at the screen.
///
/// While it speaks, the wake-word listener is muted: otherwise Vox would hear
/// itself, and a question like "Say yes to confirm" could confirm itself.
@MainActor
final class SpeechOutput: NSObject {
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var speaking = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        if speaking == 0 { onStart?() }
        speaking += 1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    fileprivate func utteranceEnded() {
        speaking = max(0, speaking - 1)
        if speaking == 0 { onFinish?() }
    }
}

extension SpeechOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }
}
