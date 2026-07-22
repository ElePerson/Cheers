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
            Text("Claim response recorded").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
        } else if actionable {
            HStack(spacing: 8) {
                Button("Decline") { resolve("reject") }
                    .buttonStyle(.bordered).tint(Theme.textSecondary).disabled(busy)
                Button("Accept claim") { resolve("accept") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(busy)
            }
            .font(.system(size: 13, weight: .semibold))
        }
    }

    private var claimId: String? { message.contentData?["claim_id"]?.stringValue }
    private var actionable: Bool {
        guard let requester = message.contentData?["requester_id"]?.stringValue else { return false }
        return requester == app.session?.userId && claimId != nil
    }

    private func resolve(_ decision: String) {
        guard let api = app.api, let claimId, !busy else { return }
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
