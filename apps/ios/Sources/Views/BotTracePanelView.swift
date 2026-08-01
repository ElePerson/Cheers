import SwiftUI

/// One persistent activity control owned by a bot message.
///
/// Tap 1 opens the complete step list. Tap 2 opens a step's detail. The main
/// conversation never expands a long timeline inline, so message reading stays
/// primary and the target does not move when a run completes.
struct BotTracePanelView: View {
    let channelId: String
    let msgId: String
    var liveEvents: [TraceEntryDto] = []
    var isRunning = false

    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingSheet = false
    @State private var durableEvents: [TraceEntryDto]?
    @State private var loading = false
    @State private var errorText: String?

    private var displayedEvents: [TraceEntryDto] {
        durableEvents ?? liveEvents
    }

    var body: some View {
        // After the authoritative read proves a completed turn had no trace,
        // remove the speculative lazy-load control.
        if durableEvents?.isEmpty == true, !isRunning {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                Divider()
                    .overlay(Theme.border.opacity(0.45))

                Button {
                    showingSheet = true
                } label: {
                    HStack(spacing: Theme.space2) {
                        statusIcon
                            .frame(width: 16)
                        Text(summary)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: Theme.space2)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(isRunning ? Theme.textSecondary : Theme.textMuted)
                    .frame(minHeight: Theme.hitMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(summary)
                .accessibilityHint("Shows this message's agent activity")
            }
            .sheet(isPresented: $showingSheet) {
                TraceActivitySheet(
                    events: displayedEvents,
                    isRunning: isRunning,
                    loading: loading,
                    errorText: errorText,
                    retry: { Task { await loadDurableTrace() } }
                )
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.bgSurface)
                .task { await loadDurableTrace() }
            }
            .onChange(of: liveEvents) { _, latest in
                // While running, live socket data is newer than any durable read.
                if isRunning { durableEvents = latest }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if loading && displayedEvents.isEmpty {
            ProgressView().controlSize(.mini)
        } else if isRunning {
            if reduceMotion {
                Image(systemName: "circle.dotted")
            } else {
                ProgressView().controlSize(.mini)
            }
        } else if displayedEvents.contains(where: { $0.status == "failed" || $0.phase.contains("failed") }) {
            Image(systemName: "xmark.circle")
                .foregroundStyle(Theme.danger)
        } else {
            Image(systemName: "checkmark.circle")
        }
    }

    private var summary: String {
        let events = displayedEvents
        if isRunning {
            let current = events.last(where: { $0.status == "in_progress" || $0.status == "pending" })
                ?? events.last
            return current?.compactLabel ?? String(localized: "Running")
        }
        guard !events.isEmpty else { return String(localized: "Agent activity") }
        return String(localized: "\(events.count) actions")
    }

    private func loadDurableTrace() async {
        guard let api = app.api, !loading else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let fetched = try await api.fetchMessageTrace(channelId: channelId, msgId: msgId)
            if !isRunning || fetched.count >= liveEvents.count {
                durableEvents = fetched
            }
        } catch {
            errorText = String(localized: "Failed to load activity.")
            if durableEvents == nil, !liveEvents.isEmpty { durableEvents = liveEvents }
        }
    }
}

private struct TraceActivitySheet: View {
    let events: [TraceEntryDto]
    let isRunning: Bool
    let loading: Bool
    let errorText: String?
    let retry: () -> Void

    var body: some View {
        ChannelActionSheet(
            "Agent activity",
            systemImage: "bolt.horizontal.circle",
            showsActionBar: isRunning
        ) {
            Group {
                if events.isEmpty, loading {
                    ProgressView("Loading activity…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if events.isEmpty, let errorText {
                    ContentUnavailableView {
                        Label("Couldn’t load activity", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorText)
                    } actions: {
                        Button("Retry", action: retry)
                            .buttonStyle(.borderedProminent)
                    }
                } else if events.isEmpty {
                    ContentUnavailableView(
                        "No activity recorded",
                        systemImage: "checkmark.circle",
                        description: Text("This response did not record any agent steps.")
                    )
                } else {
                    List {
                        ForEach(events) { entry in
                            Group {
                                if entry.hasDetail {
                                    NavigationLink(value: entry) {
                                        TraceStepRow(entry: entry)
                                    }
                                } else {
                                    TraceStepRow(entry: entry)
                                }
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(
                                top: Theme.space1,
                                leading: Theme.space4,
                                bottom: Theme.space1,
                                trailing: Theme.space4
                            ))
                        }
                    }
                    .listStyle(.plain)
                    .listRowSpacing(Theme.space1)
                    .scrollContentBackground(.hidden)
                    .background(Theme.bgSurface)
                }
            }
            .background(Theme.bgSurface)
            .navigationDestination(for: TraceEntryDto.self) { entry in
                TraceDetailView(entry: entry)
            }
        } actions: {
            HStack(spacing: Theme.space2) {
                ProgressView().controlSize(.mini)
                Text("Running")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct TraceStepRow: View {
    let entry: TraceEntryDto

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space3) {
            Image(systemName: entry.category.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(entry.statusTone)
                .frame(width: 18, height: 22)

            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(entry.category.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let target = entry.targetLabel {
                    Text(target)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: Theme.space2)

            HStack(spacing: Theme.space2) {
                if let duration = entry.durationLabel {
                    Text(duration)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.textMuted)
                }
                statusGlyph
            }
            .frame(minHeight: 22)
        }
        .frame(minHeight: Theme.hitMin)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch entry.status {
        case "in_progress", "pending":
            ProgressView().controlSize(.mini)
        case "failed":
            Image(systemName: "xmark.circle").foregroundStyle(Theme.danger)
        default:
            Image(systemName: "checkmark.circle").foregroundStyle(Theme.textMuted)
        }
    }
}

private struct TraceDetailView: View {
    let entry: TraceEntryDto

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.space2) {
                    Text(entry.detailTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: Theme.space2) {
                        Image(systemName: entry.status == "failed" ? "xmark.circle" : "checkmark.circle")
                        Text(entry.statusLabel)
                        if let duration = entry.durationLabel { Text("· \(duration)") }
                    }
                    .font(.caption)
                    .foregroundStyle(entry.status == "failed" ? Theme.danger : Theme.textSecondary)
                }
                .padding(.vertical, Theme.space1)
            }

            if let path = entry.path {
                Section("File") {
                    Text(path)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if let diff = entry.diff {
                Section("Changes") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(diff)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textBody)
                            .textSelection(.enabled)
                    }
                }
            }

            if let input = entry.data?["input"] ?? entry.data?["raw_input"] {
                jsonSection("Input", value: input)
            }
            if let output = entry.data?["output"] ?? entry.data?["raw_output"] {
                jsonSection("Output", value: output)
            } else if let message = entry.message?.nilIfEmpty {
                Section("Result") {
                    Text(message).font(.subheadline).textSelection(.enabled)
                }
            }
            if let decision = entry.decision?.nilIfEmpty {
                Section("Decision") {
                    Text(decision).font(.subheadline).textSelection(.enabled)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bgApp)
        .navigationTitle(entry.category.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func jsonSection(_ title: LocalizedStringKey, value: JSONValue) -> some View {
        Section {
            Text(value.prettyPrinted)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textBody)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text(title)
        }
    }
}

private enum TraceCategory {
    case read, edit, write, command, plan, approval, tool, done, failure

    var label: String {
        switch self {
        case .read: return String(localized: "Read")
        case .edit: return String(localized: "Edit")
        case .write: return String(localized: "Write")
        case .command: return String(localized: "Run")
        case .plan: return String(localized: "Plan")
        case .approval: return String(localized: "Approval")
        case .tool: return String(localized: "Tool")
        case .done: return String(localized: "Done")
        case .failure: return String(localized: "Failed")
        }
    }

    var symbol: String {
        switch self {
        case .read: return "doc.text.magnifyingglass"
        case .edit: return "pencil"
        case .write: return "square.and.pencil"
        case .command: return "terminal"
        case .plan: return "list.bullet"
        case .approval: return "checkmark.shield"
        case .tool: return "wrench"
        case .done: return "checkmark"
        case .failure: return "xmark.circle"
        }
    }
}

private extension TraceEntryDto {
    var category: TraceCategory {
        if kind == "approval" || phase == "approval" { return .approval }
        if status == "failed" || phase.contains("failed") { return .failure }
        let haystack = [phase, title, data?["tool_name"]?.stringValue]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if haystack.contains("edit") || diff != nil { return .edit }
        if haystack.contains("write") { return .write }
        if haystack.contains("read") || haystack.contains("search") { return .read }
        if haystack.contains("command") || haystack.contains("terminal") || haystack.contains("exec") { return .command }
        if haystack.contains("plan") { return .plan }
        if phase == "prompt_finished" { return .done }
        return .tool
    }

    var compactLabel: String {
        if let targetLabel { return "\(category.label) · \(targetLabel)" }
        return title?.nilIfEmpty ?? category.label
    }

    var targetLabel: String? {
        path?.split(separator: "/").last.map(String.init)
            ?? data?.firstString("command", "cmd", "query", "target", "tool_name")
            ?? title?.nilIfEmpty
            ?? message?.nilIfEmpty
    }

    var path: String? {
        data?.firstString("path", "file_path", "filename")
            ?? data?["input"]?.firstString("path", "file_path", "filename")
    }

    var diff: String? {
        data?.firstString("diff", "unified_diff", "patch")
            ?? data?["output"]?.firstString("diff", "unified_diff", "patch")
    }

    var durationLabel: String? {
        let milliseconds = data?["duration_ms"]?.numberValue
            ?? data?["elapsed_ms"]?.numberValue
        guard let milliseconds else { return nil }
        if milliseconds < 1_000 { return "\(Int(milliseconds))ms" }
        return String(format: "%.1fs", milliseconds / 1_000)
    }

    var hasDetail: Bool {
        if diff != nil || path != nil || decision?.nilIfEmpty != nil || message?.nilIfEmpty != nil { return true }
        guard let object = data?.objectValue else { return false }
        return !object.isEmpty
    }

    var detailTitle: String {
        if let targetLabel { return "\(category.label) · \(targetLabel)" }
        return category.label
    }

    var statusLabel: String {
        switch status {
        case "pending": return String(localized: "Pending")
        case "in_progress": return String(localized: "In progress")
        case "failed": return String(localized: "Failed")
        default: return String(localized: "Completed")
        }
    }

    var statusTone: Color {
        switch status {
        case "failed": return Theme.danger
        case "pending", "in_progress": return Theme.textSecondary
        default: return Theme.textMuted
        }
    }
}

private extension JSONValue {
    var prettyPrinted: String {
        guard let encoded = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: encoded),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8)
        else { return String(describing: self) }
        return string
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
