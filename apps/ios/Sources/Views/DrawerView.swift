import SwiftUI
import UIKit

/// The navigation hub. Top: a compact workspace bar (long-press to switch).
/// Middle: the selected workspace's channels and DMs. Bottom: a compact nav chip
/// row (Activity · Fleet · Friends) and a slim footer (profile/settings · New channel).
struct DrawerView: View {
    @Environment(AppModel.self) private var app
    @Environment(ShellModel.self) private var shell
    var convo: ConversationListModel
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0

    @State private var query = ""
    @State private var showSearch = false
    @State private var newAsDM = false
    @State private var showNew = false
    @State private var showNewWorkspace = false
    @State private var showWorkspaceAdmin = false
    @State private var workspaceAvatarImages: [String: UIImage] = [:]
    @State private var userAvatarURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                channelList
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bgSurface)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Menu {
                        workspaceMenu
                    } label: {
                        HStack(spacing: 8) {
                            workspaceGlyph
                            Text(shell.selectedWorkspace?.name ?? "All conversations")
                                .font(.headline)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("Choose workspace")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("New channel", systemImage: "number") {
                            newAsDM = false
                            showNew = true
                        }
                        Button("New direct message", systemImage: "person.crop.circle.badge.plus") {
                            newAsDM = true
                            showNew = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New conversation")

                    Button("Search", systemImage: "magnifyingglass") {
                        showSearch = true
                    }
                    .labelStyle(.iconOnly)
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        shell.push(.settings)
                    } label: {
                        AvatarView(
                            seedId: app.session?.userId ?? "me",
                            name: app.session?.displayName ?? app.session?.username,
                            size: 28,
                            imageURL: userAvatarURL
                        )
                    }
                    .accessibilityLabel("Settings")

                    Button {
                        shell.push(.activity)
                    } label: {
                        Label(
                            "Activity",
                            systemImage: shell.pendingInvites + shell.pendingApprovals > 0
                                ? "bell.badge.fill"
                                : "bell"
                        )
                    }

                    Button {
                        shell.push(.fleet)
                    } label: {
                        Label("Fleet", systemImage: "dot.radiowaves.left.and.right")
                    }

                    Button {
                        shell.push(.friends)
                    } label: {
                        Label("Friends", systemImage: "person.2")
                    }
                }
            }
            .modifier(OptionalDrawerSearch(query: $query, isPresented: $showSearch))
            .toolbarBackground(Theme.bgSurface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Theme.bgSurface, for: .bottomBar)
            .toolbarBackground(.visible, for: .bottomBar)
            .sheet(isPresented: $showWorkspaceAdmin) {
                if let workspace = shell.selectedWorkspace {
                    WorkspaceAdminSheet(workspace: workspace)
                }
            }
            .sheet(isPresented: $showNew) {
                NewConversationSheet(startAsDM: newAsDM)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showNewWorkspace) {
                NewWorkspaceSheet()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .padding(.top, topInset)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onChange(of: showSearch) { _, presented in
            if !presented {
                query = ""
            }
        }
        .task(id: workspaceAvatarRevision) {
            await loadWorkspaceAvatars()
        }
        .task(id: shell.drawerOpen) {
            guard shell.drawerOpen else { return }
            await loadUserAvatar()
        }
    }

    // MARK: Workspace bar (compact — tap OR long-press to switch)

    /// One compact row: the current workspace glyph + name, a chevron hint, and
    /// (for team workspaces) a settings gear that opens Manage workspace. Tap/long-press
    /// the name row opens the workspace switcher.
    private var workspaceGlyph: some View {
        Group {
            if let ws = shell.selectedWorkspace {
                if shell.personalWorkspace?.workspaceId == ws.workspaceId {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.online)
                        .overlay(Image(systemName: "house.fill").font(.subheadline.weight(.medium)).foregroundStyle(.white))
                } else if let image = workspaceAvatarImages[ws.workspaceId] {
                    Image(uiImage: image)
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.avatarColor(for: ws.workspaceId))
                        .overlay(Text(Theme.initials(ws.name)).font(.subheadline.weight(.semibold)).foregroundStyle(.white))
                }
            } else {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.bgRaised)
                    .overlay(Image(systemName: "square.grid.2x2").font(.subheadline.weight(.medium)).foregroundStyle(Theme.textSecondary))
            }
        }
        .frame(width: 28, height: 28)
    }

    @ViewBuilder
    private var workspaceMenu: some View {
        Button { shell.selectWorkspace(nil) } label: { Label("All conversations", systemImage: "square.grid.2x2") }
        if let personal = shell.personalWorkspace {
            Button { shell.selectWorkspace(personal.workspaceId) } label: { Label("Personal", systemImage: "house") }
        }
        ForEach(shell.workspaces) { ws in
            Button { shell.selectWorkspace(ws.workspaceId) } label: {
                if let image = workspaceAvatarImages[ws.workspaceId] {
                    Label {
                        Text(ws.name)
                    } icon: {
                        Image(uiImage: image)
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFill()
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                } else {
                    Label(ws.name, systemImage: "building.2")
                }
            }
        }
        if shell.isLoadingWorkspaces,
           shell.personalWorkspace == nil,
           shell.workspaces.isEmpty {
            Label("Loading workspaces…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(Theme.textMuted)
        }
        Divider()
        Button { showNewWorkspace = true } label: {
            Label("New workspace", systemImage: "plus")
        }
        Button { showWorkspaceAdmin = true } label: {
            Label("Workspace Config", systemImage: "gearshape")
        }
        .disabled(!canConfigureSelectedWorkspace)
    }

    // MARK: Channel + DM list

    private var scopedRows: [ConversationRow] {
        convo.rows.filter { row in
            guard shell.matchesFilter(row.channel) else { return false }
            guard !query.isEmpty else { return true }
            let q = query.lowercased()
            return row.channel.displayName.lowercased().contains(q)
                || row.previewText.lowercased().contains(q)
        }
    }

    private var workspaceAvatarRevision: String {
        shell.workspaces
            .map { "\($0.workspaceId):\($0.avatarUrl ?? "")" }
            .joined(separator: "|")
    }

    private var canConfigureSelectedWorkspace: Bool {
        guard let selected = shell.selectedWorkspace else { return false }
        return shell.personalWorkspace?.workspaceId != selected.workspaceId
    }

    private func resolveAvatarURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
        guard let base = app.baseURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return URL(string: raw, relativeTo: components.url)?.absoluteURL
    }

    private func loadWorkspaceAvatars() async {
        for workspace in shell.workspaces {
            guard workspaceAvatarImages[workspace.workspaceId] == nil,
                  let url = resolveAvatarURL(workspace.avatarUrl),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data)
            else { continue }
            workspaceAvatarImages[workspace.workspaceId] = image
        }
    }

    private func loadUserAvatar() async {
        guard let profile = try? await app.api?.getMe() else { return }
        userAvatarURL = resolveAvatarURL(profile.avatarURL)
    }

    private var channelList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let channels = scopedRows.filter { !$0.channel.isDM }
                let dms = scopedRows.filter { $0.channel.isDM }
                if !channels.isEmpty {
                    sectionHeader(String(localized: "Channels"))
                    ForEach(channels) { row in drawerRow(row) }
                }
                if !dms.isEmpty {
                    sectionHeader(String(localized: "Direct messages"))
                    ForEach(dms) { row in drawerRow(row) }
                }
            }
            .padding(.vertical, Theme.space1)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 18)
            .padding(.top, Theme.space3)
            .padding(.bottom, Theme.space1)
    }

    private func drawerRow(_ row: ConversationRow) -> some View {
        Button {
            shell.openChat(row.channel)
        } label: {
            HStack(spacing: Theme.space3) {
                if row.channel.isDM {
                    ChannelAvatarView(channel: row.channel, size: 36)
                } else if row.channel.isVoice {
                    Image(systemName: "waveform")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Theme.bgRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    Text("#")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Theme.bgRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                Text(row.channel.displayName)
                    .font(.body)
                    .foregroundStyle(Theme.textBody)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if row.unreadCount > 0 {
                    Text(row.unreadCount > 99 ? "99+" : String(row.unreadCount))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(minWidth: 18)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, Theme.rowVertical)
            .frame(minHeight: Theme.hitMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

/// `searchable` reserves navigation-bar drawer space even while inactive on
/// some iOS versions. Attach it only for an explicit search session so the
/// closed drawer stays compact.
private struct OptionalDrawerSearch: ViewModifier {
    @Binding var query: String
    @Binding var isPresented: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPresented {
            content.searchable(
                text: $query,
                isPresented: $isPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search conversations"
            )
        } else {
            content
        }
    }
}
