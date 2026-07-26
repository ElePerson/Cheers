import SwiftUI

/// Small action footer attached to a normal bot reply, matching the web card.
struct TaskClaimConfirmationFooter: View {
    @Environment(AppModel.self) private var app
    let message: MessageDto
    let channelId: String
    @State private var busy = false
    @State private var resolved: Bool

    init(message: MessageDto, channelId: String) {
        self.message = message
        self.channelId = channelId
        _resolved = State(initialValue: message.contentData?["resolved"]?.boolValue == true)
    }

    var body: some View {
        if resolved {
            Label("Claim response recorded", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())
        } else if actionable {
            TaskClaimActionButtons(busy: busy, onDecision: resolve)
        }
    }

    private var claimId: String? { message.contentData?["claim_id"]?.stringValue }
    private var actionable: Bool {
        guard let requester = message.contentData?["requester_id"]?.stringValue else { return false }
        return requester == app.session?.userId && claimId != nil
    }

    private func resolve(_ decision: String) {
        guard let api = app.api, let claimId, !busy else { return }
        NativeFeedback.selection()
        busy = true
        Task {
            defer { busy = false }
            do {
                try await api.resolveTaskClaim(channelId: channelId, claimId: claimId, decision: decision)
                resolved = true
            } catch {
                // Message-level feedback stays compact; a retry remains available.
            }
        }
    }
}

struct TaskClaimActionButtons: View {
    let busy: Bool
    let onDecision: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { onDecision("reject") } label: {
                Label("Decline", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Theme.textSecondary)

            Button { onDecision("accept") } label: {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Accept claim", systemImage: "checkmark")
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Theme.accent)
        }
        .controlSize(.small)
        .font(.subheadline.weight(.semibold))
        .disabled(busy)
    }
}
