import SwiftUI

/// Compact channel entry for ACP re-authentication. Detailed content and all
/// actions live in the shared native channel sheet.
struct AuthRequiredCardView: View {
    let message: MessageDto
    @State private var showSheet = false

    private var request: AuthRequiredRequest? {
        AuthRequiredRequest(contentData: message.contentData)
    }

    private var botName: String {
        message.senderName ?? "Agent"
    }

    var body: some View {
        if let request {
            if request.resolved {
                resolvedLine(request)
            } else {
                pendingCard(request)
            }
        } else {
            SystemMessageView(message: message)
        }
    }

    private func pendingCard(_ request: AuthRequiredRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(botName) needs sign-in", systemImage: "person.badge.key")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack {
                Text(request.title)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Button("Review", systemImage: "chevron.right") { showSheet = true }
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
            AuthRequiredSheetView(
                channelId: message.channelId,
                botName: botName,
                request: request
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func resolvedLine(_ request: AuthRequiredRequest) -> some View {
        let label: String = {
            if request.chosenAction == "retry" { return "Auth acknowledged — retrying" }
            if request.chosenAction == "cancel" || request.resolvedKind == "timeout" {
                return "Auth cancelled"
            }
            return "Auth resolved"
        }()
        return Label(label, systemImage: "key.fill")
            .font(.caption)
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.space5)
            .padding(.vertical, 4)
    }
}

private struct AuthRequiredSheetView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let channelId: String
    let botName: String
    let request: AuthRequiredRequest

    @State private var busy: String?
    @State private var errorMessage: String?

    private var isOwner: Bool {
        guard let owner = request.botOwnerId, let me = app.session?.userId else { return false }
        return owner == me
    }

    var body: some View {
        ChannelActionSheet("Agent sign-in", systemImage: "person.badge.key") {
            Form {
                Section {
                    LabeledContent("Agent", value: botName)
                    LabeledContent("Request", value: request.title)
                    if let methodId = request.methodId {
                        LabeledContent("Method", value: methodId)
                    }
                }

                Section("Details") {
                    Text(request.description)
                    if let link = request.link, let url = URL(string: link) {
                        Link(destination: url) {
                            Label("Open login page", systemImage: "safari")
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
        } actions: {
            if isOwner {
                HStack(spacing: 12) {
                    Button("Cancel", role: .destructive) {
                        Task { await acknowledge("cancel") }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled(busy != nil)

                    Button {
                        Task { await acknowledge("retry") }
                    } label: {
                        if busy == "retry" {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("I've signed in").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(busy != nil)
                }
            } else {
                Label("Waiting for the agent owner", systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func acknowledge(_ action: String) async {
        guard let api = app.api, busy == nil else { return }
        busy = action
        errorMessage = nil
        defer { busy = nil }
        do {
            _ = try await api.ackAuthRequired(
                channelId: channelId,
                requestId: request.requestId,
                action: action
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
