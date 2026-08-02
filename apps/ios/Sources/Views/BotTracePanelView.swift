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
        coalescedEvents(durableEvents ?? liveEvents)
    }

    /// The trace table is append-only for auditability, but the activity sheet
    /// presents one step per correlated operation. Fold tool deltas by
    /// `tool_call_id` and approval lifecycle rows by `request_id`, retaining the
    /// descriptive fields from the opening event when a terminal delta omits them.
    private func coalescedEvents(_ events: [TraceEntryDto]) -> [TraceEntryDto] {
        var result: [TraceEntryDto] = []
        var indexes: [String: Int] = [:]

        for event in events.sorted(by: { $0.traceSeq < $1.traceSeq }) {
            // REST and the live socket can contain the same persisted row. Use
            // its durable id as a fallback key so merging both sources does not
            // duplicate lifecycle-independent events.
            let key = event.operationKey ?? "event:\(event.id)"
            guard let index = indexes[key] else {
                indexes[key] = result.count
                result.append(event)
                continue
            }

            let opening = result[index]
            var merged = event
            merged.id = opening.id
            merged.traceSeq = opening.traceSeq
            merged.title = event.title ?? opening.title
            merged.message = event.message ?? opening.message
            if let openingData = opening.data, let terminalData = event.data {
                merged.data = openingData.merging(withNewer: terminalData)
            } else {
                merged.data = event.data ?? opening.data
            }
            merged.requestId = event.requestId ?? opening.requestId
            merged.approvalKind = event.approvalKind ?? opening.approvalKind
            merged.decision = event.decision ?? opening.decision
            merged.optionId = event.optionId ?? opening.optionId
            merged.actorId = event.actorId ?? opening.actorId
            result[index] = merged
        }
        return result
    }

    var body: some View {
        // After the authoritative read proves a completed turn had no trace,
        // remove the speculative lazy-load control.
        if durableEvents?.isEmpty == true, !isRunning {
            EmptyView()
        } else {
            Button {
                showingSheet = true
            } label: {
                HStack(spacing: 8) {
                    statusIcon
                        .frame(width: 18)
                    Text(summary)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summary)
            .accessibilityHint("Shows this message's agent activity")
            .sheet(isPresented: $showingSheet) {
                TraceActivitySheet(
                    events: displayedEvents,
                    isRunning: isRunning,
                    loading: loading,
                    errorText: errorText,
                    retry: { Task { await loadDurableTrace() } }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .task { await loadDurableTrace() }
            }
            .onChange(of: liveEvents) { _, latest in
                // A terminal socket delta can be less descriptive than the
                // opening row returned by REST. Merge both sources through the
                // same lifecycle fold instead of replacing the durable rows.
                if isRunning {
                    durableEvents = coalescedEvents((durableEvents ?? []) + latest)
                }
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
            durableEvents = isRunning
                ? coalescedEvents(fetched + liveEvents)
                : fetched
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Agent activity")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    if isRunning {
                        ToolbarItem(placement: .bottomBar) {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Running")
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationDestination(for: TraceEntryDto.self) { entry in
                    TraceDetailView(entry: entry)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
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
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
    }
}

private struct TraceStepRow: View {
    let entry: TraceEntryDto

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: entry.category.symbol)
                .font(.body)
                .foregroundStyle(entry.statusTone)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.compactLabel)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let target = entry.targetLabel {
                    if target != entry.compactLabel && !entry.compactLabel.contains(target) {
                        Text(target)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: Theme.space2) {
                if let duration = entry.durationLabel {
                    Text(duration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textMuted)
                }
                statusGlyph
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
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
            Section("Overview") {
                LabeledContent("Type", value: entry.category.label)
                LabeledContent("Status") {
                    Label(
                        entry.statusLabel,
                        systemImage: entry.status == "failed" ? "xmark.circle" : statusSymbol
                    )
                    .foregroundStyle(entry.status == "failed" ? Color.red : Color.secondary)
                }
                if let duration = entry.durationLabel {
                    LabeledContent("Duration", value: duration)
                }
                if let target = entry.targetLabel {
                    LabeledContent("Target", value: target)
                }
            }

            if let path = entry.path {
                Section("File") {
                    Text(path)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if let diff = entry.diff {
                Section("Changes · +\(diffAdditions) −\(diffDeletions)") {
                    ForEach(Array(diff.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, raw in
                        let line = String(raw)
                        Text(line.isEmpty ? " " : line)
                            .font(.caption.monospaced())
                            .foregroundStyle(diffForeground(line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .listRowBackground(diffBackground(line))
                            .listRowSeparator(.hidden)
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
        .navigationTitle(entry.category.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusSymbol: String {
        switch entry.status {
        case "pending", "in_progress": "circle.dotted"
        default: "checkmark.circle"
        }
    }

    private var diffLines: [String] {
        entry.diff?.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) ?? []
    }

    private var diffAdditions: Int {
        diffLines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
    }

    private var diffDeletions: Int {
        diffLines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
    }

    private func diffForeground(_ line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") { return .secondary }
        if line.hasPrefix("@@") { return .blue }
        if line.hasPrefix("+") { return .green }
        if line.hasPrefix("-") { return .red }
        return .primary
    }

    private func diffBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return Color.green.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color.red.opacity(0.08) }
        if line.hasPrefix("@@") { return Color.blue.opacity(0.08) }
        return .clear
    }

    @ViewBuilder
    private func jsonSection(_ title: LocalizedStringKey, value: JSONValue) -> some View {
        Section {
            Text(value.prettyPrinted)
                .font(.caption.monospaced())
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
    var operationKey: String? {
        if let requestId = requestId?.nilIfEmpty {
            return "approval:\(requestId)"
        }
        if let toolCallId = data?.firstString("tool_call_id", "toolCallId")?.nilIfEmpty {
            return "tool:\(toolCallId)"
        }
        return nil
    }

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
    /// Merge an append-only lifecycle delta over an earlier payload. Object keys
    /// from the terminal event win recursively, while omitted (or explicitly
    /// null) keys keep the richer opening-event detail such as tool input/diff.
    func merging(withNewer newer: JSONValue) -> JSONValue {
        if case .null = newer { return self }
        guard case .object(let oldObject) = self,
              case .object(let newObject) = newer
        else { return newer }

        var result = oldObject
        for (key, value) in newObject {
            if let oldValue = result[key] {
                result[key] = oldValue.merging(withNewer: value)
            } else if value != .null {
                result[key] = value
            }
        }
        return .object(result)
    }

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
