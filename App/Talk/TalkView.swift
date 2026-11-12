import SwiftUI

struct TalkView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TalkModel.shared
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let reason = model.unavailableReason {
                    ContentUnavailableView {
                        Label("Talk Unavailable", systemImage: "apple.intelligence")
                    } description: {
                        Text(reason)
                    } actions: {
                        Button("Try Again") { model.prepare() }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                    }
                } else {
                    conversation
                }
            }
            // Same light gray as the other tabs; bubbles and cards sit on it like list rows.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            // No title on Talk: just the settings button, in the same spot as the other tabs.
            .safeAreaInset(edge: .top, spacing: 0) {
                TabHeader(title: nil, tab: .talk)
            }
        }
        .tint(.orange)
        .task { model.prepare() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, model.isLive { model.toggleLive() }
            if phase == .active { model.prepare() }
        }
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                    if model.isResponding {
                        TypingIndicator().id("typing")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(.snappy, value: model.messages)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if model.messages.isEmpty && !model.isLive {
                    EmptyTalkView()
                }
            }
            .onChange(of: model.messages.count) {
                withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: model.isResponding) { _, responding in
                if responding { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            inputBar
        }
    }

    private var inputBar: some View {
        VStack(spacing: 10) {
            if model.isLive || model.voice.errorMessage != nil {
                LiveStatusCard(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .center, spacing: 8) {
                TextField("Message", text: $model.draft)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { model.sendDraft() }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))

                if !model.draft.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        model.sendDraft()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .orange)
                    }
                    .accessibilityLabel("Send")
                    .transition(.scale.combined(with: .opacity))
                }

                Button {
                    model.toggleLive()
                } label: {
                    Image(systemName: model.isLive ? "stop.circle.fill" : "waveform.circle.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, model.isLive ? Color.red : Color.orange)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(model.isLive ? "Stop Live Talk" : "Start Live Talk")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        .animation(.snappy, value: model.isLive)
        .animation(.snappy, value: model.draft.isEmpty)
    }
}

// MARK: - Messages

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        case .assistant:
            HStack {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .textSelection(.enabled)
                Spacer(minLength: 48)
            }
        case .event(let systemImage):
            // Shown like an attachment the assistant sent: left-aligned, tappable when it links somewhere.
            HStack {
                if let link = message.link {
                    Button {
                        AppNavigation.shared.open(link)
                    } label: {
                        AttachmentCard(text: message.text, systemImage: systemImage, isLink: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens it")
                } else {
                    AttachmentCard(text: message.text, systemImage: systemImage, isLink: false)
                }
                Spacer(minLength: 48)
            }
        case .error:
            Label(message.text, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct TypingIndicator: View {
    var body: some View {
        HStack {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.bold))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer()
        }
    }
}

private struct EmptyTalkView: View {
    @AppStorage(TalkSettings.wakeWordEnabledKey) private var wakeWordEnabled = false
    @AppStorage(TalkSettings.wakeWordKey) private var wakeWord = TalkSettings.defaultWakeWord

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.orange.gradient)
            Text("Ask Me Anything")
                .font(.title3.weight(.semibold))
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .allowsHitTesting(false)
    }

    private var hint: String {
        let example = "“wake me up at 7 on weekdays” or “remind me to call mom tomorrow at 6”"
        if wakeWordEnabled, !wakeWord.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Tap the waveform and say “\(wakeWord), …”, or type below. Try \(example)."
        }
        return "Tap the waveform to talk, or type below. Try \(example)."
    }
}

// MARK: - Live status

private struct LiveStatusCard: View {
    let model: TalkModel

    var body: some View {
        let voice = model.voice
        HStack(spacing: 14) {
            indicator(for: voice.phase, level: voice.level)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !voice.transcript.isEmpty {
                    Text(voice.transcript)
                        .font(.subheadline)
                        .lineLimit(3)
                        .contentTransition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: voice.transcript)
    }

    private var status: String {
        let voice = model.voice
        if let error = voice.errorMessage, !model.isLive { return error }
        if let hint = model.ignoredHint { return hint }
        switch voice.phase {
        case .off:
            return "Live Talk is off"
        case .listening:
            if model.awaitingFollowUp { return "I'm listening…" }
            if let wakeWord = TalkSettings.activeWakeWord { return "Listening for “\(wakeWord)”…" }
            return "Listening…"
        case .thinking:
            return "Thinking…"
        case .speaking:
            return "Speaking…"
        }
    }

    @ViewBuilder
    private func indicator(for phase: LiveVoice.Phase, level: Float) -> some View {
        switch phase {
        case .listening:
            ZStack {
                Circle().fill(Color.orange.opacity(0.2))
                    .scaleEffect(1 + CGFloat(level) * 0.6)
                Circle().fill(Color.orange.gradient)
                    .frame(width: 18, height: 18)
            }
            .animation(.easeOut(duration: 0.12), value: level)
        case .thinking:
            ProgressView()
        case .speaking:
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.orange)
                .symbolEffect(.variableColor.iterative)
        case .off:
            Image(systemName: "mic.slash.fill")
                .foregroundStyle(.secondary)
        }
    }
}

/// "Alarm updated · 7:00 AM · Weekdays" shown as a card: icon, title, details, chevron.
private struct AttachmentCard: View {
    let text: String
    let systemImage: String
    let isLink: Bool

    var body: some View {
        let parts = text.components(separatedBy: " · ")
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.orange.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(parts.first ?? text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if parts.count > 1 {
                    Text(parts.dropFirst().joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            if isLink {
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }
}
