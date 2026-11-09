import Foundation
import FoundationModels
import Observation

struct ChatMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case user, assistant, event(systemImage: String), error
    }

    let id = UUID()
    let role: Role
    let text: String
}

/// The Talk tab's conversation with Apple's on-device model, by text or by voice.
@MainActor
@Observable
final class TalkModel {
    static let shared = TalkModel()

    private(set) var messages: [ChatMessage] = []
    private(set) var isResponding = false
    /// Why the on-device model can't be used, if it can't.
    private(set) var unavailableReason: String?
    /// Brief hint shown after a sentence was ignored for lacking the wake word.
    private(set) var ignoredHint: String?
    /// True for a few seconds after only the wake word was said: the next sentence needs no wake word.
    private(set) var awaitingFollowUp = false

    var draft = ""
    let voice = LiveVoice()

    @ObservationIgnored private var session: LanguageModelSession?
    @ObservationIgnored private var lastActivity = Date.distantPast
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var followUpDeadline: Date?
    @ObservationIgnored private var hintTask: Task<Void, Never>?

    /// Start a fresh conversation after this much inactivity (keeps context small and the clock fresh).
    private static let sessionLifetime: TimeInterval = 10 * 60
    private static let followUpWindow: TimeInterval = 8

    private init() {
        voice.onUtterance = { [weak self] sentence in
            await self?.handleSpoken(sentence)
        }
        // Read fresh each time, so a wake word changed by voice applies right away.
        voice.contextualStrings = { TalkSettings.activeWakeWord.map { [$0] } ?? [] }
    }

    // MARK: - Lifecycle

    /// Checks model availability and warms the model up so the first reply is fast.
    func prepare() {
        unavailableReason = Self.availabilityMessage()
        guard unavailableReason == nil else { return }
        currentSession().prewarm()
    }

    var isLive: Bool { voice.phase != .off }

    /// Starts Live Talk (used by the Control Center button). Waits a moment so the app is
    /// fully in the foreground before the microphone starts.
    func startLive() {
        guard !isLive else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !isLive { toggleLive() }
        }
    }

    func toggleLive() {
        if isLive {
            voice.stop()
            awaitingFollowUp = false
        } else {
            Task { await voice.start() }
        }
    }

    func clear() {
        messages.removeAll()
        session = nil
        awaitingFollowUp = false
    }

    // MARK: - Input

    /// Typed messages always get a reply (the wake word only applies to Live Talk).
    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { _ = await respond(to: text) }
    }

    private func handleSpoken(_ sentence: String) async {
        var request = sentence

        if let wakeWord = TalkSettings.activeWakeWord {
            if let deadline = followUpDeadline, deadline > .now {
                // They said just the wake word a moment ago; this is the actual request.
                endFollowUp()
            } else if let rest = WakeWord.strip(wakeWord, from: sentence) {
                guard !rest.isEmpty else {
                    beginFollowUp()
                    if TalkSettings.speakReplies { voice.speak("Yes?") } else { voice.resumeListening() }
                    return
                }
                request = rest
            } else {
                showIgnoredHint("Ignored. Start with “\(wakeWord)”")
                voice.resumeListening()
                return
            }
        }

        let reply = await respond(to: request)
        if let reply, TalkSettings.speakReplies {
            voice.speak(reply)
        } else {
            voice.resumeListening()
        }
    }

    // MARK: - Model

    /// Sends a message to the model and returns its reply. Requests run one at a time.
    @discardableResult
    func respond(to text: String) async -> String? {
        messages.append(ChatMessage(role: .user, text: text))

        let previous = queue
        let work = Task { @MainActor () -> String? in
            await previous?.value
            isResponding = true
            defer { isResponding = false }
            do {
                let reply = try await ask(text)
                messages.append(ChatMessage(role: .assistant, text: reply))
                return reply
            } catch {
                let message = Self.describe(error)
                messages.append(ChatMessage(role: .error, text: message))
                return message
            }
        }
        queue = Task { _ = await work.value }
        return await work.value
    }

    func addEvent(_ text: String, systemImage: String) {
        messages.append(ChatMessage(role: .event(systemImage: systemImage), text: text))
    }

    private func ask(_ text: String) async throws -> String {
        if let reason = Self.availabilityMessage() {
            unavailableReason = reason
            return reason
        }
        do {
            return try await currentSession().respond(to: text).content
        } catch let error as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = error else { throw error }
            // The conversation got too long for the small model: start over and retry once.
            session = nil
            return try await currentSession().respond(to: text).content
        }
    }

    private func currentSession() -> LanguageModelSession {
        if let session, Date().timeIntervalSince(lastActivity) < Self.sessionLifetime {
            lastActivity = .now
            return session
        }
        let fresh = LanguageModelSession(
            tools: [
                ListItemsTool(),
                CreateAlarmTool(), EditAlarmTool(),
                CreateTodoTool(), EditTodoTool(),
                SetTimerTool(), CancelTimersTool(),
                UpdateSettingsTool(),
            ],
            instructions: Self.instructions()
        )
        session = fresh
        lastActivity = .now
        return fresh
    }

    private static func instructions() -> String {
        let now = Date().formatted(.dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
        return """
        You are a friendly, quick assistant inside the user's alarm clock app. You manage their \
        alarms, to-dos, timers and settings using your tools.
        Reply in one or two short sentences of plain text with no markdown, lists or emoji, \
        because replies may be read aloud.
        Rules:
        - Wake-up times and "wake me" requests are alarms (createAlarm). "Remind me to..." and tasks \
        are to-dos (createTodo). Countdowns like "in 10 minutes" for cooking are timers (setTimer).
        - Alarm hours use the 24-hour clock: 7 PM is 19.
        - To change or delete something, call editAlarm or editTodo with how the user referred to it. \
        If it is unclear what exists, call listItems first.
        - Never invent alarms or to-dos. After a tool runs, briefly confirm what was done.
        The current date and time is \(now).
        """
    }

    // MARK: - Helpers

    private func beginFollowUp() {
        followUpDeadline = Date().addingTimeInterval(Self.followUpWindow)
        awaitingFollowUp = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.followUpWindow))
            guard let self, let deadline = self.followUpDeadline, deadline <= .now else { return }
            self.endFollowUp()
        }
    }

    private func endFollowUp() {
        followUpDeadline = nil
        awaitingFollowUp = false
    }

    private func showIgnoredHint(_ text: String) {
        ignoredHint = text
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.ignoredHint = nil
        }
    }

    private static func availabilityMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "Talk uses Apple Intelligence's on-device model, which this iPhone doesn't support."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings to use Talk."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again in a few minutes."
        case .unavailable:
            return "The on-device model isn't available right now."
        @unknown default:
            return "The on-device model isn't available right now."
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation:
                return "Sorry, I can't help with that."
            case .assetsUnavailable:
                return "The on-device model isn't available right now."
            default:
                break
            }
        }
        return "Something went wrong. Please try again."
    }
}
