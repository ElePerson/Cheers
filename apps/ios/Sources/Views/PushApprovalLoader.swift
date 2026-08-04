import SwiftUI

/// Loads a pending ACP approval from push deep-link metadata and presents the
/// shared Approval sheet. Used when the user taps a permission notification
/// (or when lock-screen Approve/Deny cannot resolve in the background).
struct PushApprovalLoader: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let channelId: String
    let requestId: String
    var activity: ActivityModel

    @State private var botName = "Agent"
    @State private var request: PermissionRequest?
    @State private var errorText: String?

    var body: some View {
        Group {
            if let request {
                ApprovalSheetView(channelId: channelId, botName: botName, request: request)
            } else if let errorText {
                ContentUnavailableView(
                    "Approval unavailable",
                    systemImage: "checkmark.shield",
                    description: Text(errorText)
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            } else {
                ProgressView("Loading approval…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
    }

    private func load() async {
        if let item = activity.pending.first(where: {
            $0.request.requestId == requestId && $0.channelId == channelId
        }) {
            botName = item.botName
            request = item.request
            return
        }

        guard let api = app.api else {
            errorText = "Sign in again to review this request."
            return
        }

        do {
            let page = try await api.listMessages(channelId: channelId, limit: 50)
            if let message = page.messages.first(where: { message in
                guard message.msgType == "permission",
                      let parsed = PermissionRequest(contentData: message.contentData)
                else { return false }
                return parsed.requestId == requestId
            }), let parsed = PermissionRequest(contentData: message.contentData) {
                botName = message.senderName ?? "Agent"
                request = parsed
                return
            }
            errorText = "This request was already resolved or is no longer available."
        } catch {
            errorText = "Couldn’t load this approval. Open the channel to review it."
        }
    }
}
