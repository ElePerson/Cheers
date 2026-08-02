import SwiftUI

// The conversation list surface now lives in `ChatsHomeView` (inside the
// drawer-first `AppShellView`). This file keeps the shared row view and the
// `Hashable` conformance those and the drawer reuse.

extension ConversationRow: Hashable {
    static func == (lhs: ConversationRow, rhs: ConversationRow) -> Bool {
        lhs.channel.channelId == rhs.channel.channelId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(channel.channelId)
    }
}

// MARK: - Row

struct ConversationRowView: View {
    let row: ConversationRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ChannelAvatarView(channel: row.channel, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.channel.displayName)
                        .font(.body.weight(row.unreadCount > 0 ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let ws = row.workspaceName {
                        Text("· \(ws)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(TimeFormat.listStamp(row.lastActivity))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(row.unreadCount > 0 ? Color.accentColor : Color.secondary)
                        .lineLimit(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(previewLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if row.unreadCount > 0 {
                        Text(row.unreadCount > 99 ? "99+" : String(row.unreadCount))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(minWidth: 18)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var previewLine: String {
        var text = row.previewText
        if text.count > 160 {
            text = String(text.prefix(160)) + "…"
        }
        return text
    }
}
