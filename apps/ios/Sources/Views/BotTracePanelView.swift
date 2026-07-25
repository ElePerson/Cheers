import SwiftUI

/// Collapsible "Agent steps" panel for a completed bot turn.
///
/// Mirrors web `BotTracePanel`: the toggle is always cheap; the durable
/// timeline (`GET …/messages/:msgId/trace`) loads only on first expand so
/// opening a channel never eagerly fetches every turn's traces.
struct BotTracePanelView: View {
    let channelId: String
    let msgId: String

    @Environment(AppModel.self) private var app

    @State private var expanded = false
    @State private var events: [TraceEntryDto]?
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        // Once loaded empty, hide entirely (no noise under finished turns).
        if events?.isEmpty == true, !expanded {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Theme.space1) {
                Button(action: toggle) {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text(titleLabel)
                            .font(.system(size: 11, weight: .medium))
                        if approvalCount > 0 {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 10, weight: .medium))
                            Text("\(approvalCount)")
                                .font(.system(size: 10).monospacedDigit())
                        }
                        if loading {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.textMuted)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? String(localized: "Hide agent steps") : String(localized: "Show agent steps"))

                if expanded {
                    if let events, !events.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.space1) {
                            ForEach(events) { entry in
                                TraceStepRow(entry: entry)
                            }
                        }
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Theme.border)
                                .frame(width: 1)
                        }
                        .padding(.leading, 5)
                    } else if events?.isEmpty == true, !loading, errorText == nil {
                        Text("No steps recorded.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted)
                            .padding(.leading, Theme.space2)
                    } else if let errorText, !loading {
                        HStack(spacing: Theme.space2) {
                            Text(errorText)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.danger)
                            Button("Retry") { Task { await load() } }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.link)
                        }
                        .padding(.leading, Theme.space2)
                    }
                }
            }
            .frame(maxWidth: 360, alignment: .leading)
        }
    }

    private var titleLabel: String {
        if let events {
            return String(localized: "Agent steps · \(events.count)")
        }
        return String(localized: "Agent steps")
    }

    private var approvalCount: Int {
        events?.filter { $0.kind == "approval" }.count ?? 0
    }

    private func toggle() {
        expanded.toggle()
        if expanded, events == nil, !loading {
            Task { await load() }
        }
    }

    private func load() async {
        guard let api = app.api, !loading else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            events = try await api.fetchMessageTrace(channelId: channelId, msgId: msgId)
        } catch {
            // Leave events nil so the next expand retries.
            errorText = String(localized: "Failed to load steps.")
        }
    }
}

private struct TraceStepRow: View {
    let entry: TraceEntryDto

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space2) {
            Image(systemName: meta.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(meta.tone)
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.space2) {
                    Text(entry.title?.nilIfEmpty ?? meta.label)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(1)
                    if let status = entry.status?.nilIfEmpty {
                        Text(statusLabel(status))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                    }
                }
                if entry.kind == "approval", let decision = entry.decision?.nilIfEmpty {
                    Text(decision)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                } else if entry.kind != "approval", let message = entry.message?.nilIfEmpty {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var meta: (symbol: String, tone: Color, label: String) {
        if entry.kind == "approval" {
            switch entry.approvalKind {
            case "resolved":
                let ok = (entry.decision ?? "").hasPrefix("allow")
                return ok
                    ? ("checkmark", Theme.textMuted, String(localized: "Approved"))
                    : ("xmark", Theme.danger, String(localized: "Denied"))
            case "expired":
                return ("xmark", Theme.textFaint, String(localized: "Expired"))
            case "rejected":
                return ("xmark", Theme.textFaint, String(localized: "Rejected"))
            case "auto_allowed":
                return ("checkmark", Theme.textMuted, String(localized: "Auto-allowed"))
            default:
                return ("checkmark.shield", Theme.warning, String(localized: "Approval"))
            }
        }
        switch entry.phase {
        case "tool_call", "tool_call_update":
            return ("wrench", Theme.textMuted, String(localized: "Tool"))
        case "plan":
            return ("list.bullet", Theme.textMuted, String(localized: "Plan"))
        case "prompt_finished":
            return ("checkmark", Theme.textMuted, String(localized: "Done"))
        case "prompt_started":
            return ("bolt", Theme.textMuted, String(localized: "Start"))
        case "prompt_failed", "terminal_ack_failed":
            return ("xmark.circle", Theme.danger, String(localized: "Failed"))
        default:
            return ("clock", Theme.textFaint, entry.phase.isEmpty ? String(localized: "Event") : entry.phase)
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "pending": return String(localized: "Pending")
        case "in_progress": return String(localized: "In progress")
        case "completed": return String(localized: "Completed")
        case "failed": return String(localized: "Failed")
        default:
            return status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
