import AVFoundation
import Speech
import SwiftUI

/// Growing multiline composer pinned to the bottom of the chat screen.
/// Visuals follow the web MessageComposer: raised capsule, strong border that
/// turns indigo on focus, 32pt indigo send button.
struct ComposerView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Draft and keyboard focus live inside this leaf view. A keystroke now
    /// invalidates only the composer subtree, never the chat timeline.
    @State private var text: String
    let clearTick: Int
    let placeholder: String
    let isSending: Bool
    let streamingCount: Int
    let onSend: (String) async -> Bool
    let onStopStreaming: () async -> Void
    let channelId: String
    let api: APIClient?
    var onChooseSession: () -> Void = {}
    var onModelSettings: () -> Void = {}
    var onUploadFile: () -> Void = {}
    var onBrowseFiles: () -> Void = {}
    var onAddContext: () -> Void = {}
    /// "@" typeahead pool (group tokens + channel members) and the pick
    /// callback registering the selection for routing (ChatModel.pickedMentions).
    var mentionPool: [MentionCandidate] = []
    var onMentionPicked: (MentionCandidate) -> Void = { _ in }

    @FocusState private var isFocused: Bool
    @State private var dictation = ComposerDictationController()

    init(
        initialText: String,
        clearTick: Int,
        placeholder: String,
        isSending: Bool,
        streamingCount: Int = 0,
        onSend: @escaping (String) async -> Bool,
        onStopStreaming: @escaping () async -> Void = {},
        channelId: String,
        api: APIClient?,
        onChooseSession: @escaping () -> Void = {},
        onModelSettings: @escaping () -> Void = {},
        onUploadFile: @escaping () -> Void = {},
        onBrowseFiles: @escaping () -> Void = {},
        onAddContext: @escaping () -> Void = {},
        mentionPool: [MentionCandidate] = [],
        onMentionPicked: @escaping (MentionCandidate) -> Void = { _ in }
    ) {
        _text = State(initialValue: initialText)
        self.clearTick = clearTick
        self.placeholder = placeholder
        self.isSending = isSending
        self.streamingCount = streamingCount
        self.onSend = onSend
        self.onStopStreaming = onStopStreaming
        self.channelId = channelId
        self.api = api
        self.onChooseSession = onChooseSession
        self.onModelSettings = onModelSettings
        self.onUploadFile = onUploadFile
        self.onBrowseFiles = onBrowseFiles
        self.onAddContext = onAddContext
        self.mentionPool = mentionPool
        self.onMentionPicked = onMentionPicked
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private var showStop: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending && streamingCount > 0
    }

    // MARK: @-mention typeahead

    /// The active "@" token: the last "@" must start a word and the text after
    /// it must contain no whitespace. The caret is assumed to sit at the end of
    /// the draft — SwiftUI's TextField exposes no caret position, and appending
    /// is where mobile typing overwhelmingly happens.
    private var mentionToken: (range: Range<String.Index>, query: String)? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        if atIndex > text.startIndex, !text[text.index(before: atIndex)].isWhitespace {
            return nil
        }
        let query = text[text.index(after: atIndex)...]
        guard !query.contains(where: \.isWhitespace) else { return nil }
        return (atIndex..<text.endIndex, String(query))
    }

    /// Matches for the active token, ranked bots → group tokens → people (web
    /// parity). Capped at 5 rows so the list never buries the input.
    private var mentionMatches: [MentionCandidate] {
        guard let token = mentionToken, !mentionPool.isEmpty else { return [] }
        let q = token.query.lowercased()
        let hits = mentionPool.filter {
            q.isEmpty || $0.label.lowercased().contains(q)
                || ($0.sublabel?.lowercased().contains(q) ?? false)
        }
        // Stable rank sort: decorate with the original index as tie-break.
        return hits.enumerated()
            .sorted { ($0.element.kind.rawValue, $0.offset) < ($1.element.kind.rawValue, $1.offset) }
            .prefix(5)
            .map(\.element)
    }

    private func pick(_ candidate: MentionCandidate) {
        guard let token = mentionToken else { return }
        text.replaceSubrange(token.range, with: "@\(candidate.label) ")
        onMentionPicked(candidate)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !mentionMatches.isEmpty {
                mentionPicker
            }
            inputRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Theme.bgApp)
        .onChange(of: clearTick) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { text = "" }
        }
    }

    private var mentionPicker: some View {
        VStack(spacing: 0) {
            ForEach(mentionMatches) { candidate in
                Button { pick(candidate) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: candidate.kind == .bot ? "sparkles"
                            : candidate.kind == .group ? "person.3" : "person")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(candidate.kind == .bot ? Theme.accent : Theme.textSecondary)
                            .frame(width: 22)
                        Text(candidate.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if let sub = candidate.sublabel, !sub.isEmpty {
                            Text(candidate.kind == .group ? sub : "@\(sub)")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if candidate.kind == .bot {
                            Text("BOT")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)   // HIG tap target
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.bgRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .padding(.bottom, 6)
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button { onUploadFile() } label: { Label("Upload file", systemImage: "paperclip") }
                Button { onBrowseFiles() } label: { Label("Channel files", systemImage: "folder") }
                Button { onAddContext() } label: { Label("Add context", systemImage: "link.badge.plus") }
                Divider()
                Button { onChooseSession() } label: { Label("Choose session", systemImage: "square.stack.3d.up") }
                Button { onModelSettings() } label: { Label("Model & bot settings", systemImage: "slider.horizontal.3") }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(.thinMaterial, in: Circle())
                    .frame(width: Theme.hitMin, height: Theme.hitMin)
                    .contentShape(Rectangle())
            }
            .padding(.leading, 2)
            .accessibilityLabel("Add message options")

            TextField(placeholder, text: $text, axis: .vertical)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...8)
                .focused($isFocused)
                .padding(.vertical, 11)
                .accessibilityLabel(placeholder)

            dictationButton

            Button {
                if showStop {
                    Task { await onStopStreaming() }
                    return
                }
                // Sending is an intentional completion point for a mobile
                // draft. Clear focus first so UIKit reliably dismisses the
                // software keyboard even while the network request is pending.
                isFocused = false
                let draft = text
                Task {
                    if await onSend(draft) {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { text = "" }
                    }
                }
            } label: {
                Group {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: showStop ? "stop.fill" : "paperplane.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(canSend || showStop ? Color.white : Theme.textFaint)
                    }
                }
                .frame(width: 36, height: 36)
                .background(showStop ? Theme.danger : (canSend ? Theme.accent : Theme.bgSelected.opacity(0.5)))
                .clipShape(Circle())
                .shadow(color: canSend ? Theme.accent.opacity(0.22) : .clear, radius: 5, y: 2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .disabled(!canSend && !showStop)
            .padding(.trailing, 2)
            .accessibilityLabel(isSending ? "Sending message" : (showStop ? "Stop response" : "Send message"))
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(isFocused ? Theme.accentHover.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .alert("Voice dictation", isPresented: Binding(
            get: { dictation.errorMessage != nil },
            set: { if !$0 { dictation.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { dictation.errorMessage = nil }
        } message: {
            Text(dictation.errorMessage ?? "")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isFocused = false }
            }
        }
    }

    private var dictationButton: some View {
        Button {
            Task {
                await dictation.toggle(channelId: channelId, api: api) { transcript in
                    let separator = text.isEmpty || text.last?.isWhitespace == true ? "" : " "
                    // A final transcript can grow the multiline field by
                    // several rows. Insert it in one non-animated transaction
                    // so UIKit does not animate the keyboard/layout through
                    // intermediate composer states.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        text += separator + transcript
                        isFocused = true
                    }
                }
            }
        } label: {
            Group {
                if dictation.isWorking {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                } else {
                    Image(systemName: dictation.isRecording ? "stop.circle.fill" : "mic")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(dictation.isRecording ? Color.red : Theme.textSecondary)
                }
            }
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
        }
        .disabled(dictation.isWorking || api == nil)
        .accessibilityLabel(dictation.isRecording ? "Stop voice dictation" : "Start voice dictation")
    }
}

/// Captures one short composer utterance. A configured Gateway adapter is used
/// first so provider credentials never reach the phone; iOS Speech is only the
/// intentional no-adapter fallback. Neither path persists raw audio.
@MainActor
@Observable
private final class ComposerDictationController {
    private(set) var isRecording = false
    private(set) var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var pcm = PCM16Accumulator()
    @ObservationIgnored private var usesServerAdapter = false
    @ObservationIgnored private var onTranscript: ((String) -> Void)?

    func toggle(channelId: String, api: APIClient?, onTranscript: @escaping (String) -> Void) async {
        if isRecording {
            await stop(channelId: channelId, api: api)
        } else {
            await start(channelId: channelId, api: api, onTranscript: onTranscript)
        }
    }

    private func start(channelId: String, api: APIClient?, onTranscript: @escaping (String) -> Void) async {
        guard let api else { return }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let capability = try await api.dictationCapability(channelId: channelId)
            usesServerAdapter = capability.adapterConfigured && capability.adapterKind == "stepfun"
            self.onTranscript = onTranscript
            pcm = PCM16Accumulator()

            if !usesServerAdapter {
                try await requestNativeSpeechPermission()
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = false
                if #available(iOS 13, *) { request.requiresOnDeviceRecognition = false }
                recognitionRequest = request
                let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
                    ?? SFSpeechRecognizer()
                guard let recognizer, recognizer.isAvailable else {
                    throw DictationError.speechUnavailable
                }
                recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    guard let self else { return }
                    if let result, result.isFinal {
                        self.deliver(result.bestTranscription.formattedString)
                    } else if let error, self.isRecording {
                        self.errorMessage = error.localizedDescription
                    }
                }
            } else {
                try await requestMicrophonePermission()
            }

            try configureAudioAndStartTap()
            isRecording = true
        } catch {
            cleanup()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func stop(channelId: String, api: APIClient?) async {
        guard isRecording else { return }
        isRecording = false
        let adapterAudio = usesServerAdapter ? pcm.data : Data()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        if usesServerAdapter {
            isWorking = true
            defer { isWorking = false; cleanup() }
            guard !adapterAudio.isEmpty else {
                errorMessage = "No speech was captured. Please try again."
                return
            }
            do {
                guard let api else { return }
                deliver(try await api.dictate(channelId: channelId, pcm16: adapterAudio))
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        } else {
            // The recognizer delivers its final result asynchronously after endAudio.
            recognitionTask?.finish()
        }
    }

    private func configureAudioAndStartTap() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            guard let self else { return }
            if self.usesServerAdapter {
                self.pcm.append(buffer)
            } else {
                self.recognitionRequest?.append(buffer)
            }
        }
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func deliver(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onTranscript?(trimmed)
        cleanup()
    }

    private func cleanup() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
        usesServerAdapter = false
    }

    private func requestMicrophonePermission() async throws {
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else { throw DictationError.microphoneDenied }
    }

    private func requestNativeSpeechPermission() async throws {
        try await requestMicrophonePermission()
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw DictationError.speechDenied }
    }

    private enum DictationError: LocalizedError {
        case microphoneDenied, speechDenied, speechUnavailable
        var errorDescription: String? {
            switch self {
            case .microphoneDenied: return "Allow microphone access in Settings to use voice dictation."
            case .speechDenied: return "Allow Speech Recognition in Settings to use the on-device dictation fallback."
            case .speechUnavailable: return "Speech Recognition is unavailable on this device right now."
            }
        }
    }
}

/// Thread-safe PCM conversion for StepFun: 16 kHz, mono, little-endian Int16.
/// The AudioEngine tap may run off the main actor, so this intentionally keeps
/// its mutable buffer behind a lock.
private final class PCM16Accumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data { lock.withLock { storage } }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let source = channels[0]
        let sourceCount = Int(buffer.frameLength)
        guard sourceCount > 0 else { return }
        let sourceRate = buffer.format.sampleRate
        let outputCount = max(1, Int((Double(sourceCount) * 16_000.0 / sourceRate).rounded()))
        var converted = Data(capacity: outputCount * MemoryLayout<Int16>.size)
        for outputIndex in 0..<outputCount {
            let sourceIndex = min(sourceCount - 1, Int(Double(outputIndex) * sourceRate / 16_000.0))
            let normalized = max(-1.0, min(1.0, source[sourceIndex]))
            var sample = Int16((normalized * Float(Int16.max)).rounded()).littleEndian
            withUnsafeBytes(of: &sample) { converted.append(contentsOf: $0) }
        }
        lock.withLock {
            guard storage.count + converted.count <= 8 * 1024 * 1024 else { return }
            storage.append(converted)
        }
    }
}
