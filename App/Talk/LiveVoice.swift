import AVFoundation
import Foundation
import Observation
import Speech

/// Hands-free conversation loop: listen → detect the end of a sentence → hand it off →
/// (optionally) speak the reply → listen again.
///
/// Speech recognition runs on device. The microphone stays open the whole time, but audio is
/// only fed to the recognizer while listening, so the assistant never hears its own voice.
@MainActor
@Observable
final class LiveVoice: NSObject {
    enum Phase: Equatable {
        case off, listening, thinking, speaking
    }

    private(set) var phase: Phase = .off
    /// What has been heard so far in the current sentence.
    private(set) var transcript = ""
    /// Microphone level, 0…1, for the listening animation.
    private(set) var level: Float = 0
    var errorMessage: String?

    /// Called with each finished sentence. The handler must end by calling `speak(_:)` or `resumeListening()`.
    @ObservationIgnored var onUtterance: ((String) async -> Void)?
    /// Words to bias recognition toward (e.g. the wake word).
    @ObservationIgnored var contextualStrings: [String] = []

    /// How long a pause ends a sentence.
    private static let endOfSentenceSilence: Duration = .milliseconds(900)

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let feed = AudioFeed()
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var silenceTimer: Task<Void, Never>?
    @ObservationIgnored private var voice: AVSpeechSynthesisVoice?

    override init() {
        super.init()
        voice = Self.bestVoice()
        synthesizer.delegate = self
    }

    // MARK: - Control

    func start() async {
        guard phase == .off else { return }
        errorMessage = nil

        guard await Self.requestPermissions() else {
            errorMessage = "Allow Microphone and Speech Recognition in Settings to use Live Talk."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        self.recognizer = recognizer

        do {
            try startAudio()
        } catch {
            errorMessage = "Couldn't start the microphone."
            stop()
            return
        }
        phase = .listening
        startRecognition()
    }

    func stop() {
        phase = .off
        silenceTimer?.cancel()
        endRecognition()
        synthesizer.stopSpeaking(at: .immediate)
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        transcript = ""
        level = 0
    }

    /// Goes back to listening for the next sentence.
    func resumeListening() {
        guard phase != .off else { return }
        transcript = ""
        phase = .listening
        startRecognition()
    }

    /// Speaks a reply, then automatically resumes listening.
    func speak(_ text: String) {
        guard phase != .off else { return }
        endRecognition()
        phase = .speaking
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synthesizer.speak(utterance)
    }

    // MARK: - Audio

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw CocoaError(.featureUnsupported) }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(feed: feed) { [weak self] level in
            Task { @MainActor in self?.level = level }
        })
        audioEngine.prepare()
        try audioEngine.start()
    }

    // MARK: - Recognition

    private func startRecognition() {
        endRecognition()
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let generation = UUID()
        self.generation = generation
        self.request = request
        feed.set(request)

        task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler { [weak self] text, isFinal, failed in
            Task { @MainActor in self?.handleResult(generation: generation, text: text, isFinal: isFinal, failed: failed) }
        })
    }

    private func endRecognition() {
        silenceTimer?.cancel()
        feed.set(nil)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        generation = UUID()
    }

    private func handleResult(generation: UUID, text: String?, isFinal: Bool, failed: Bool) {
        guard generation == self.generation, phase == .listening else { return }

        if let text, !text.isEmpty, text != transcript {
            transcript = text
            restartSilenceTimer()
        }

        if isFinal {
            finishSentence()
        } else if failed {
            // Usually "no speech detected" after a long quiet spell. Just keep listening.
            if transcript.isEmpty { startRecognition() } else { finishSentence() }
        }
    }

    private func restartSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.endOfSentenceSilence)
            guard !Task.isCancelled else { return }
            self?.finishSentence()
        }
    }

    private func finishSentence() {
        guard phase == .listening else { return }
        let sentence = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        endRecognition()
        guard !sentence.isEmpty else {
            startRecognition()
            return
        }
        phase = .thinking
        Task {
            if let onUtterance {
                await onUtterance(sentence)
            } else {
                resumeListening()
            }
        }
    }

    // MARK: - Nonisolated helpers (run on audio / recognition threads)

    private nonisolated static func makeTap(
        feed: AudioFeed,
        onLevel: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            feed.append(buffer)
            onLevel(level(of: buffer))
        }
    }

    private nonisolated static func makeResultHandler(
        _ forward: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            forward(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    private nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let decibels = 20 * log10(max(sqrt(sum / Float(count)), 0.000_000_1))
        return max(0, min(1, (decibels + 50) / 40))
    }

    private static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    /// The highest-quality installed voice for the user's language.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: language)
    }
}

extension LiveVoice: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.phase == .speaking { self.resumeListening() }
        }
    }
}

/// Thread-safe hand-off of microphone buffers to whichever recognition request is current.
private final class AudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = request
        lock.unlock()
        request?.append(buffer)
    }
}
