import SwiftUI

/// Activity — things that need *me*: pending approvals (top) + invites.
/// Matches `docs/arch/CLIENT_NAV_IA.md` §5. Approvals used to live only in Fleet.
struct ActivityView: View {
    var activity: ActivityModel
    @State private var sheetItem: ApprovalItem?

    private var isEmpty: Bool {
        activity.pending.isEmpty && activity.invites.isEmpty
    }

    var body: some View {
        ScreenScaffold(title: "Activity") {
            Group {
                if isEmpty {
                    ComingSoon(icon: "bell.badge", text: "Approvals and invites appear here")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if !activity.pending.isEmpty {
                                sectionHeader("Needs approval", icon: "shield.lefthalf.filled", tint: Theme.warning)
                                ForEach(activity.pending) { item in
                                    approvalCard(item)
                                }
                            }
                            if !activity.invites.isEmpty {
                                sectionHeader("Invites", icon: "envelope", tint: Theme.accent)
                                ForEach(activity.invites) { invite in
                                    inviteCard(invite)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .refreshable { await activity.loadInvites() }
                }
            }
        }
        .sheet(item: $sheetItem) { item in
            ApprovalSheetView(channelId: item.channelId, botName: item.botName, request: item.request)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func sectionHeader(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(tint)
            Text(title.uppercased())
                .font(.system(size: 11.5, weight: .bold)).tracking(0.7)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 4).padding(.top, 12).padding(.bottom, 2)
    }

    private func approvalCard(_ item: ApprovalItem) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.warning).frame(width: 3)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    AvatarView(seedId: item.message.senderId ?? item.id, name: item.botName, size: 30)
                    Text(item.request.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                if let command = item.request.command {
                    Text(command)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(Theme.bgApp)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                Text("\(item.botName) · #\(item.channelId.prefix(6))")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Button { sheetItem = item } label: {
                    Text("Review")
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func inviteCard(_ invite: NotificationDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: invite.isChannelInvite ? "number" : "square.grid.2x2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Theme.bgRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(invite.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            if let by = invite.invitedBy {
                Text("\(by) invited you to join")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 8) {
                Button { Task { await activity.acceptInvite(invite) } } label: {
                    Text("Accept")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                Button { Task { await activity.declineInvite(invite) } } label: {
                    Text("Decline")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.bgRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
