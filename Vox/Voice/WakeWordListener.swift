import AVFoundation
import Speech
import VoxCore

/// Hands `request` to the audio thread safely while the main actor swaps it.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ new: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); request = new; lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); let current = request; lock.unlock()
        current?.append(buffer)
    }
}

/// Always-on listening for the wake word ("Balcha, open safari").
///
/// One audio engine runs continuously; recognition tasks are restarted after
/// every command, on errors, and every ~50 s (long tasks drift and slow down).
/// The decision of *when* a command is complete lives in `WakeWordTracker`
/// (VoxCore, unit-tested).
@MainActor
final class WakeWordListener {
    var onAwake: ((String) -> Void)?
    var onCommand: ((String) -> Void)?
    var onTimeout: (() -> Void)?
    /// Every transcript, for the "Last heard" diagnostic.
    var onHeard: ((String) -> Void)?

    private(set) var isRunning = false
    /// While true, everything heard is ignored (Vox is talking).
    private var muted = false
    private var config = WakeWordConfig()
    private var tracker = WakeWordTracker(config: WakeWordConfig())
    private var contextualStrings: [String] = []

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private let box = RequestBox()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var taskStartedAt = Date()
    private var ticker: Timer?
    private var consecutiveErrors = 0

    private let maxTaskSeconds: TimeInterval = 50

    func configure(_ config: WakeWordConfig, vocabulary: [String]) {
        self.config = config
        tracker = WakeWordTracker(config: config)
        contextualStrings = Array((config.phrases + vocabulary).prefix(100))
    }

    func start() throws {
        guard !isRunning else { return }
        guard let recognizer, recognizer.isAvailable else { throw VoiceError.recognizerUnavailable }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(box))
        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
        consecutiveErrors = 0
        restartTask()

        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        generation += 1
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        box.set(nil)
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        tracker.reset()
    }

    /// Ignore the microphone while Vox speaks; unmuting starts a fresh
    /// transcript so Vox's own words are never parsed.
    func setMuted(_ on: Bool) {
        guard muted != on else { return }
        muted = on
        if on {
            tracker.reset()
        } else if isRunning {
            restartTask()
        }
    }

    // MARK: Private

    private func restartTask() {
        guard isRunning, let recognizer else { return }
        generation += 1
        let myGeneration = generation
        task?.cancel()
        request?.endAudio()
        tracker.reset()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings
        request.addsPunctuation = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        box.set(request)
        taskStartedAt = Date()

        task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler { [weak self] text, ended in
            Task { @MainActor in self?.receive(text: text, ended: ended, generation: myGeneration) }
        })
    }

    private func receive(text: String?, ended: Bool, generation: Int) {
        guard generation == self.generation, isRunning, !muted else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if let text {
            consecutiveErrors = 0
            onHeard?(text)
            if case let .awake(command) = tracker.update(transcript: text, at: now) {
                onAwake?(command)
            }
        }
        if ended {
            // The recognizer finished (silence, error, or limit). If a command
            // was in progress, fire what we have; then listen again.
            if tracker.isAwake, case let .fire(command) = tracker.tick(at: now + 1_000) {
                onCommand?(command)
            }
            if text == nil { consecutiveErrors += 1 }
            let delay = min(Double(consecutiveErrors) * 0.5, 5)
            Task { @MainActor [weak self] in
                if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                guard let self, self.isRunning, generation == self.generation else { return }
                self.restartTask()
            }
        }
    }

    private func tick() {
        guard isRunning, !muted else { return }
        switch tracker.tick(at: Date().timeIntervalSinceReferenceDate) {
        case let .fire(command):
            onCommand?(command)
            restartTask()
        case .timedOut:
            onTimeout?()
            restartTask()
        case .none, .awake:
            if !tracker.isAwake, Date().timeIntervalSince(taskStartedAt) > maxTaskSeconds {
                restartTask()
            }
        }
    }

    nonisolated private static func makeTap(_ box: RequestBox) -> AVAudioNodeTapBlock {
        { buffer, _ in
            box.append(buffer)
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
