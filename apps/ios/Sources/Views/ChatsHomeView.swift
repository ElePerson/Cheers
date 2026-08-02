import SwiftUI

/// The app's home surface is a chat, not a list. This host renders the current
/// channel's `ChatView` (rebuilt when the channel changes) or, before any channel
/// is chosen, an empty state pointing at the drawer. All switching happens in the
/// drawer (`DrawerView`).
struct ChatRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(ShellModel.self) private var shell
    var convo: ConversationListModel

    var body: some View {
        Group {
            if let channel = shell.currentChannel {
                ChatView(model: app.chatModels.model(for: channel), listModel: convo)
                    .id(channel.channelId)   // remount the view per channel; the model itself is cached
            } else {
                emptyState
            }
        }
        .navigationBarHidden(shell.currentChannel == nil)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(Theme.textFaint)
            Text("No conversation open")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgApp)
    }
}
