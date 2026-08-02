import SwiftUI

/// Inline ACP approval rendered only while action is required. Resolved results
/// live in agent activity/audit and are intentionally absent from the chat.
struct ApprovalCardView: View {
    let message: MessageDto
    @State private var showSheet = false

    private var request: PermissionRequest? {
        PermissionRequest(contentData: message.contentData)
    }

    private var botName: String {
        message.senderName ?? "Agent"
    }

    var body: some View {
        if let request {
            if request.resolved {
                EmptyView()
            } else {
                pendingCard(request)
            }
        } else {
            // Not an actionable card (missing request id) — plain system text.
            SystemMessageView(message: message)
        }
    }

    // MARK: Pending

    private func pendingCard(_ request: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(botName) requests permission", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            if let command = request.command {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Text(request.title)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Button("Review", systemImage: "chevron.right") { showSheet = true }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.space5)
        .padding(.vertical, 6)
        .sheet(isPresented: $showSheet) {
            ApprovalSheetView(channelId: message.channelId, botName: botName, request: request)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
