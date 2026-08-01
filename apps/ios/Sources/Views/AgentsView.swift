import SwiftUI

/// Fleet — bot roster + create/manage. Approvals live in Activity
/// (`docs/arch/CLIENT_NAV_IA.md` §5); this screen deep-links when any are pending.
struct FleetView: View {
    @Environment(AppModel.self) private var app
    @Environment(ShellModel.self) private var shell
    var activity: ActivityModel
    @State private var model = AgentsModel()
    @State private var showOnboarding = false
    @State private var selectedBot: BotDto?
    @State private var searchText = ""
    @State private var searchPresented = false

    private var filteredBots: [BotDto] {
        guard !searchText.isEmpty else { return model.bots }
        return model.bots.filter { bot in
            bot.name.localizedCaseInsensitiveContains(searchText)
                || (bot.statusText?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        ScreenScaffold(title: "Fleet", titleDisplayMode: .inline) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if activity.pending.count > 0 {
                        Button { shell.push(.activity) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .foregroundStyle(Theme.warning)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(activity.pending.count) waiting on you")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Review in Activity")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.textFaint)
                            }
                            .padding(12)
                            .background(Theme.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    sectionHeader("Bots")
                    summaryStrip.padding(.vertical, 2)
                    if model.isLoading && model.bots.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else if model.bots.isEmpty {
                        emptyState
                    } else if filteredBots.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ForEach(filteredBots) { bot in
                            Button { selectedBot = bot } label: {
                                botRow(bot)
                            }
                            .buttonStyle(.plain)
                            if bot.id != filteredBots.last?.id {
                                Divider().overlay(Theme.border).padding(.leading, 60)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .refreshable { await model.load(); await activity.loadInvites() }
        }
        .searchable(
            text: $searchText,
            isPresented: $searchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search fleet"
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") {
                    showOnboarding = true
                }
                .labelStyle(.iconOnly)

                Button("Search", systemImage: "magnifyingglass") {
                    searchPresented = true
                }
                .labelStyle(.iconOnly)
            }
        }
        .task {
            model.attach(app)
            await model.loadIfNeeded()
        }
        .sheet(isPresented: $showOnboarding) {
            BotOnboardingView(existingBots: model.bots) {
                Task { await model.load() }
            }
        }
        .sheet(item: $selectedBot) { bot in
            BotDetailView(bot: bot) {
                Task { await model.load() }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = model.errorMessage {
                Text(message).font(.system(size: 13)).foregroundStyle(Theme.danger)
            } else {
                Text("No agents yet")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("Create one here, then connect it from the machine that will run it — this phone can't host an agent itself.")
                    .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showOnboarding = true } label: {
                    Label("Add a bot", systemImage: "plus")
                        .font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 16)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11.5, weight: .bold)).tracking(0.7)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 4).padding(.top, 12).padding(.bottom, 2)
    }

    private var summaryStrip: some View {
        HStack(spacing: 7) {
            summaryChip(dot: Theme.online, "\(model.onlineCount) online")
            summaryChip(dot: Theme.textFaint, "\(model.offlineCount) offline")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryChip(dot: Color, _ label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(label).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Theme.bgRaised)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func botRow(_ bot: BotDto) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(seedId: bot.botId, name: bot.name, size: 44)
                Circle()
                    .fill(bot.isDisabled == true ? Theme.danger : (bot.online ? Theme.online : Theme.textFaint))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Theme.bgApp, lineWidth: 2.5))
                    .offset(x: 1, y: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(bot.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text("BOT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.botBadgeText)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Theme.botBadgeBg)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    if bot.isDisabled == true {
                        Text("OFF")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Theme.danger.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                Text(statusLine(bot))
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityHint("Opens bot management")
    }

    private func statusLine(_ bot: BotDto) -> String {
        if bot.isDisabled == true { return "Disabled" }
        if let text = bot.statusText, !text.isEmpty {
            if let emoji = bot.statusEmoji, !emoji.isEmpty { return "\(emoji) \(text)" }
            return text
        }
        return bot.online ? "Online" : "Offline"
    }
}
