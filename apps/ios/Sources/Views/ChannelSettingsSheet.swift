import SwiftUI

/// Name, purpose, visibility, and the danger zone. Editing is gated on the same
/// client-derived `canManage` as the members sheet; the server enforces it again.
struct ChannelSettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(ShellModel.self) private var shell
    @Environment(\.dismiss) private var dismiss
    let channel: ChannelDto

    @State private var name = ""
    @State private var purpose = ""
    @State private var isPublic = true
    @State private var members: [ChannelMemberDto] = []
    @State private var isSaving = false
    @State private var savedNotice = false
    @State private var errorText: String?
    @State private var confirmDelete = false
    @State private var confirmLeave = false

    private var myRole: String? {
        guard let me = app.session?.userId else { return nil }
        return members.first { $0.memberType == "user" && $0.memberId == me }?.role
    }

    private var isGlobalAdmin: Bool {
        let role = app.session?.role ?? ""
        return role == "system_admin" || role == "admin"
    }

    private var canManage: Bool { isGlobalAdmin || myRole == "owner" || myRole == "admin" }

    private var dirty: Bool {
        name.trimmingCharacters(in: .whitespaces) != channel.name
            || purpose != (channel.purpose ?? "")
            || isPublic != (channel.channelType == "public")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
                Section("General") {
                    LabeledContent("Name") {
                        TextField("channel-name", text: $name)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(!canManage)
                    }
                    LabeledContent("Purpose") {
                        TextField("What this channel is for", text: $purpose, axis: .vertical)
                            .lineLimit(1...4)
                            .multilineTextAlignment(.trailing)
                            .disabled(!canManage)
                    }
                    if canManage && (channel.purpose?.isEmpty == false) && purpose.isEmpty {
                        Text("Clearing the purpose isn't supported by the server — it will keep the previous text.")
                            .foregroundStyle(.secondary)
                    }
                }

                if canManage && !channel.isDM {
                    Section {
                        Toggle("Public channel", isOn: $isPublic)
                    } footer: {
                        Text("Anyone in the workspace can join. Invite links require this.")
                    }
                }

                if !channel.isDM {
                    Section {
                        dangerZone
                    } header: {
                        Text("Channel access")
                    }
                }
            }
            .navigationTitle("Channel settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if canManage {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(savedNotice ? "Saved" : "Save") { Task { await save() } }
                            .disabled(!dirty || isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .task {
            name = channel.name
            purpose = channel.purpose ?? ""
            isPublic = channel.channelType == "public"
            if let api = app.api {
                members = (try? await api.listMembers(channelId: channel.channelId)) ?? []
            }
        }
        // Destructive actions get an explicit confirm with Cancel as the default —
        // deleting a channel must never be one stray tap away.
        .confirmationDialog("Delete #\(channel.name)? Messages and membership are gone for good.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete channel", role: .destructive) { Task { await deleteChannel() } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Leave #\(channel.name)?",
                            isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive) { Task { await leave() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var dangerZone: some View {
        Group {
            if myRole != nil {
                Button {
                    confirmLeave = true
                } label: {
                    Label("Leave channel", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            if canManage {
                Button {
                    confirmDelete = true
                } label: {
                    Label("Delete channel", systemImage: "trash")
                }
                .foregroundStyle(.red)
            }
        }
    }

    // MARK: Actions

    private func save() async {
        guard let api = app.api else { return }
        isSaving = true
        defer { isSaving = false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var update = ChannelUpdateRequest()
        if trimmed != channel.name { update.name = trimmed }
        if purpose != (channel.purpose ?? ""), !purpose.isEmpty { update.purpose = purpose }
        if isPublic != (channel.channelType == "public") { update.channelType = isPublic ? "public" : "private" }
        do {
            let updated = try await api.updateChannel(channelId: channel.channelId, update)
            shell.replaceCurrentChannel(updated)
            errorText = nil
            savedNotice = true
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteChannel() async {
        guard let api = app.api else { return }
        do {
            try await api.deleteChannel(channelId: channel.channelId)
            shell.clearCurrentChannel(ifMatching: channel.channelId)
            dismiss()
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func leave() async {
        guard let api = app.api else { return }
        do {
            try await api.leaveChannel(channelId: channel.channelId)
            shell.clearCurrentChannel(ifMatching: channel.channelId)
            dismiss()
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
