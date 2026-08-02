import SwiftUI

/// Activity — things that need *me*: pending approvals (top) + invites.
/// Matches `docs/arch/CLIENT_NAV_IA.md` §5. Approvals used to live only in Fleet.
struct ActivityView: View {
    var activity: ActivityModel
    @State private var sheetItem: ApprovalItem?
    @State private var searchText = ""
    @State private var searchPresented = false

    private var hasNoActivity: Bool {
        activity.pending.isEmpty && activity.invites.isEmpty
    }

    private var filteredPending: [ApprovalItem] {
        guard !searchText.isEmpty else { return activity.pending }
        return activity.pending.filter { item in
            item.botName.localizedCaseInsensitiveContains(searchText)
                || item.request.title.localizedCaseInsensitiveContains(searchText)
                || (item.request.command?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var filteredInvites: [NotificationDto] {
        guard !searchText.isEmpty else { return activity.invites }
        return activity.invites.filter { invite in
            invite.title.localizedCaseInsensitiveContains(searchText)
                || (invite.invitedBy?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var hasNoSearchResults: Bool {
        filteredPending.isEmpty && filteredInvites.isEmpty
    }

    var body: some View {
        ScreenScaffold(title: "Activity", titleDisplayMode: .inline) {
            Group {
                if hasNoActivity {
                    ComingSoon(icon: "bell.badge", text: "Approvals and invites appear here")
                } else if hasNoSearchResults {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if !filteredPending.isEmpty {
                                sectionHeader("Needs approval", icon: "shield.lefthalf.filled", tint: Theme.warning)
                                ForEach(filteredPending) { item in
                                    approvalCard(item)
                                }
                            }
                            if !filteredInvites.isEmpty {
                                sectionHeader("Invites", icon: "envelope", tint: Theme.accent)
                                ForEach(filteredInvites) { invite in
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
        .searchable(
            text: $searchText,
            isPresented: $searchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search activity"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search", systemImage: "magnifyingglass") {
                    searchPresented = true
                }
                .labelStyle(.iconOnly)
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
            Image(systemName: icon).font(.caption).foregroundStyle(tint)
            Text(title.uppercased())
                .font(.caption.weight(.bold)).tracking(0.7)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                if let command = item.request.command {
                    Text(command)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(Theme.bgApp)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                Text("\(item.botName) · #\(item.channelId.prefix(6))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Button { sheetItem = item } label: {
                    Text("Review")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Theme.bgRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(invite.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            if let by = invite.invitedBy {
                Text("\(by) invited you to join")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 8) {
                Button { Task { await activity.acceptInvite(invite) } } label: {
                    Text("Accept")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                Button { Task { await activity.declineInvite(invite) } } label: {
                    Text("Decline")
                        .font(.subheadline.weight(.semibold))
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
