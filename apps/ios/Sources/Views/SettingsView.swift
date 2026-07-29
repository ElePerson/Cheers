import SwiftUI
import AuthenticationServices
import CryptoKit
import PhotosUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(ShellModel.self) private var shell
    @State private var isSigningOut = false
    @State private var showSignOutConfirm = false
    @State private var showChangePassword = false
    @State private var showTwoFactor = false
    @State private var showPasskeys = false
    @State private var showAppleAccount = false
    @State private var showGoogleAccount = false
    @State private var showBlockedUsers = false
    @State private var showAIConsents = false
    @State private var showDeleteAccount = false
    @State private var showWorkspaceAdmin = false
    @State private var showAccountSessions = false
    @State private var showProfileEdit = false
    @State private var showSwitchServerConfirm = false

    var body: some View {
        List {
            profileSection
            serverSection
            legalSection
            accountSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bgApp)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Sign out of Cheers?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("This revokes your sessions on this server.")
        }
        .confirmationDialog(
            "Switch server?",
            isPresented: $showSwitchServerConfirm,
            titleVisibility: .visible
        ) {
            Button("Switch server", role: .destructive) {
                Task { await app.switchServer() }
            }
        } message: {
            Text("Signs you out and lets you pick a different server URL on the next login.")
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet()
        }
        .sheet(isPresented: $showTwoFactor) {
            TwoFactorSettingsView()
        }
        .sheet(isPresented: $showPasskeys) {
            PasskeySettingsView()
        }
        .sheet(isPresented: $showAppleAccount) { AppleAccountSheet() }
        .sheet(isPresented: $showGoogleAccount) { GoogleAccountSheet() }
        .sheet(isPresented: $showBlockedUsers) { BlockedUsersSheet() }
        .sheet(isPresented: $showAIConsents) { AIConsentSettingsSheet() }
        .sheet(isPresented: $showDeleteAccount) { DeleteAccountSheet() }
        .sheet(isPresented: $showWorkspaceAdmin) {
            if let workspace = shell.selectedWorkspace {
                WorkspaceAdminSheet(workspace: workspace)
            }
        }
        .sheet(isPresented: $showAccountSessions) { AccountSessionsSheet() }
        .sheet(isPresented: $showProfileEdit) { ProfileEditSheet() }
        .task { await refreshProfileSummary() }
    }

    private var displayName: String {
        let session = app.session
        if let name = session?.displayName, !name.isEmpty { return name }
        return session?.username ?? "Unknown"
    }

    private func refreshProfileSummary() async {
        guard let api = app.api, let profile = try? await api.getMe() else { return }
        app.applyProfile(displayName: profile.displayName, avatarURL: profile.avatarURL)
    }

    private var profileSection: some View {
        Section {
            Button { showProfileEdit = true } label: {
                HStack(spacing: 14) {
                    AvatarView(
                        seedId: app.session?.userId ?? "?",
                        name: displayName,
                        size: 52,
                        imageURL: app.resolveServerResourceURL(app.session?.avatarURL)
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let username = app.session?.username {
                            Text(username)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textMuted)
                        }
                        Text("Edit profile")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Theme.bgSurface)

            LabeledContent {
                Text(app.session?.userId ?? "—")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } label: {
                Text("User ID")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)
        } header: {
            sectionHeader("Profile")
        }
    }

    private var serverSection: some View {
        Section {
            LabeledContent {
                Text(app.serverURLString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } label: {
                Text("Server")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            HStack {
                Text("Realtime")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textBody)
                Spacer()
                Circle()
                    .fill(app.socketConnected ? Theme.online : Theme.textFaint)
                    .frame(width: 8, height: 8)
                Text(app.socketConnected ? "Connected" : "Offline")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
            }
            .listRowBackground(Theme.bgSurface)

            Button { showSwitchServerConfirm = true } label: {
                Text("Switch server")
                    .foregroundStyle(Theme.accent)
            }
            .listRowBackground(Theme.bgSurface)
        } header: {
            sectionHeader("Server")
        } footer: {
            Text("Switching servers signs you out. Tokens belong to one server.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textFaint)
        }
    }

    private var accountSection: some View {
        Section {
            if let workspace = shell.selectedWorkspace, workspace.kind != "personal" {
                Button { showWorkspaceAdmin = true } label: {
                    Label("Manage \(workspace.name)", systemImage: "building.2")
                        .foregroundStyle(Theme.textBody)
                }
                .listRowBackground(Theme.bgSurface)
            }

            Button { showAccountSessions = true } label: {
                Label("Devices and sessions", systemImage: "laptopcomputer.and.iphone")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Button { showChangePassword = true } label: {
                Label("Change password", systemImage: "key")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Button { showTwoFactor = true } label: {
                Label("Two-factor authentication", systemImage: "lock.shield")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Button { showPasskeys = true } label: {
                Label("Passkeys", systemImage: "person.badge.key")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Button { showAppleAccount = true } label: {
                Label("Sign in with Apple", systemImage: "apple.logo")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Button { showGoogleAccount = true } label: {
                Label("Google account", systemImage: "g.circle")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Button { showBlockedUsers = true } label: {
                Label("Blocked users", systemImage: "hand.raised")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Button { showAIConsents = true } label: {
                Label("External AI permissions", systemImage: "brain.head.profile")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Button {
                showSignOutConfirm = true
            } label: {
                HStack {
                    if isSigningOut {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isSigningOut ? "Signing out…" : "Sign out")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.danger)
                }
            }
            .disabled(isSigningOut)
            .listRowBackground(Theme.bgSurface)

            Button { showDeleteAccount = true } label: {
                Label("Delete account", systemImage: "trash")
                    .foregroundStyle(Theme.danger)
            }
            .listRowBackground(Theme.bgSurface)
        } header: {
            sectionHeader("Account")
        }
    }

    private var legalSection: some View {
        Section {
            Link(destination: AppModel.privacyPolicyURL) {
                Label("Privacy Policy", systemImage: "hand.raised")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Link(destination: AppModel.termsURL) {
                Label("Terms", systemImage: "doc.text")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Link(destination: AppModel.supportURL) {
                Label("Help & Support", systemImage: "questionmark.circle")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Link(destination: AppModel.accountDeletionURL) {
                Label("Account deletion", systemImage: "person.crop.circle.badge.minus")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)

            Link(destination: AppModel.remoteOperationSafetyURL) {
                Label("Remote Operation Safety", systemImage: "shield.checkered")
                    .foregroundStyle(Theme.textBody)
            }
            .listRowBackground(Theme.bgSurface)
        } header: {
            sectionHeader("Legal & Support")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textMuted)
    }

    private func signOut() {
        guard !isSigningOut else { return }
        isSigningOut = true
        Task {
            await app.logout()
            isSigningOut = false
        }
    }
}

// MARK: - Profile edit

private struct ProfileEditSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var statusEmoji = ""
    @State private var statusText = ""
    @State private var bio = ""
    @State private var avatarURL: URL?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isUploadingAvatar = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Section {
                        HStack(spacing: 14) {
                            AvatarView(
                                seedId: app.session?.userId ?? "?",
                                name: displayName.isEmpty ? app.session?.username : displayName,
                                size: 64,
                                imageURL: avatarURL
                            )
                            VStack(alignment: .leading, spacing: 8) {
                                PhotosPicker(selection: $pickerItem, matching: .images) {
                                    Text(isUploadingAvatar ? "Uploading…" : "Change photo")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                                .disabled(isUploadingAvatar)
                                Text("JPEG or PNG, used across Cheers clients.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                        .padding(.vertical, 4)

                        TextField("Display name", text: $displayName)
                        TextField("Status emoji", text: $statusEmoji)
                            .textInputAutocapitalization(.never)
                        TextField("Status text", text: $statusText)
                        TextField("Bio", text: $bio, axis: .vertical)
                            .lineLimit(3...6)
                    }
                    if let errorText {
                        Section {
                            Text(errorText).foregroundStyle(Theme.danger)
                        }
                    }
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isLoading || isSaving || isUploadingAvatar)
                }
            }
            .task { await load() }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await uploadAvatar(from: item) }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let me = try await app.api?.getMe()
            displayName = me?.displayName ?? app.session?.displayName ?? ""
            statusEmoji = me?.statusEmoji ?? ""
            statusText = me?.statusText ?? ""
            bio = me?.bio ?? ""
            avatarURL = app.resolveServerResourceURL(me?.avatarURL)
            if let me {
                app.applyProfile(displayName: me.displayName, avatarURL: me.avatarURL)
            }
        } catch {
            errorText = error.localizedDescription
            displayName = app.session?.displayName ?? ""
        }
    }

    private func uploadAvatar(from item: PhotosPickerItem) async {
        isUploadingAvatar = true
        defer {
            isUploadingAvatar = false
            pickerItem = nil
        }
        do {
            guard let jpeg = try await Self.jpegData(from: item) else {
                errorText = "Could not read the selected photo."
                return
            }
            let urlString = try await app.api?.uploadUserAvatar(data: jpeg, contentType: "image/jpeg")
            avatarURL = app.resolveServerResourceURL(urlString)
            app.applyProfileAvatarURL(urlString)
            errorText = nil
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// PhotosPicker's `Data` transferable is unreliable for HEIC/Live Photos;
    /// decode via UIImage and re-encode JPEG so the gateway always accepts it.
    private static func jpegData(from item: PhotosPickerItem) async throws -> Data? {
        if let data = try await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data),
           let jpeg = image.jpegData(compressionQuality: 0.88) {
            return jpeg
        }
        // Fallback: some iOS versions only expose a file URL transferable.
        if let url = try await item.loadTransferable(type: URL.self),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data),
           let jpeg = image.jpegData(compressionQuality: 0.88) {
            return jpeg
        }
        return nil
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let me = try await app.api?.updateMe(
                displayName: displayName,
                bio: bio,
                statusText: statusText,
                statusEmoji: statusEmoji
            )
            app.applyProfile(
                displayName: me?.displayName ?? displayName,
                avatarURL: me?.avatarURL ?? app.session?.avatarURL
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct ChangePasswordSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var twoFactorCode = ""
    @State private var twoFactorEnabled = false
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current password", text: $currentPassword)
                        .textContentType(.password)
                    SecureField("New password", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm new password", text: $confirmation)
                        .textContentType(.newPassword)
                } footer: {
                    Text("Changing your password signs out other sessions. This device keeps its notification registration; other devices must sign in again.")
                }

                if twoFactorEnabled {
                    Section {
                        TextField("Authenticator or backup code", text: $twoFactorCode)
                            .textContentType(.oneTimeCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } footer: {
                        Text("Required because two-factor authentication is on.")
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        save()
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .task {
                twoFactorEnabled = (try? await app.api?.twoFactorStatus().enabled) ?? false
            }
        }
    }

    private var canSave: Bool {
        let factorOk = !twoFactorEnabled || !twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !currentPassword.isEmpty && newPassword.count >= 12 && newPassword == confirmation && factorOk
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        errorText = nil
        Task {
            defer { isSaving = false }
            do {
                let code = twoFactorCode.trimmingCharacters(in: .whitespacesAndNewlines)
                try await app.changePassword(
                    currentPassword: currentPassword,
                    newPassword: newPassword,
                    twoFactorCode: twoFactorEnabled ? code : nil
                )
                dismiss()
            } catch let error as APIError {
                // Wrong password / 2FA code is also 401 — don't force a local sign-out.
                errorText = error.errorDescription ?? "Could not change password."
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

private struct AppleAuthorizationControl: View {
    @Environment(AppModel.self) private var app
    let perform: (AppleAuthorizationPayload) async throws -> Void
    @State private var challenge: AppleChallenge?
    @State private var isBusy = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 8) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
                if let nonce = challenge?.nonce {
                    request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
                }
            } onCompletion: { complete($0) }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(isBusy || challenge == nil)
            .opacity(challenge == nil ? 0.55 : 1)

            if isBusy { ProgressView().controlSize(.small) }
            if let errorText { Text(errorText).font(.system(size: 12)).foregroundStyle(Theme.danger) }
        }
        .task { await reload() }
    }

    private func reload() async {
        do { challenge = try await app.appleCapabilities(server: app.serverURLString).1 }
        catch { challenge = nil; errorText = "Sign in with Apple is unavailable on this server." }
    }

    private func complete(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let challenge,
              let tokenData = credential.identityToken,
              let codeData = credential.authorizationCode,
              let token = String(data: tokenData, encoding: .utf8),
              let code = String(data: codeData, encoding: .utf8) else {
            if case .failure(let error) = result,
               (error as? ASAuthorizationError)?.code != .canceled { errorText = error.localizedDescription }
            Task { await reload() }
            return
        }
        let payload = AppleAuthorizationPayload(
            challengeId: challenge.challengeId,
            identityToken: token,
            authorizationCode: code,
            givenName: credential.fullName?.givenName,
            familyName: credential.fullName?.familyName,
            inviteToken: nil
        )
        isBusy = true
        errorText = nil
        Task {
            defer { isBusy = false }
            do { try await perform(payload) }
            catch { errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription }
            await reload()
        }
    }
}

private struct AppleAccountSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var status: AppleIdentityStatus?
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                if let status {
                    Section {
                        Label(status.appleLinked ? "Apple account linked" : "Apple account not linked",
                              systemImage: status.appleLinked ? "checkmark.shield" : "apple.logo")
                    }
                    if !status.appleLinked {
                        Section("Link account") {
                            Text("Authenticate both your current Cheers session and Apple account. Matching email addresses are never linked automatically.")
                            AppleAuthorizationControl { payload in
                                guard let api = app.api else { throw APIError.unauthorized }
                                try await api.linkApple(payload)
                                await load()
                            }
                        }
                    } else if !status.hasPassword {
                        Section("Add a password for Web sign-in") {
                            SecureField("New password", text: $newPassword)
                            SecureField("Confirm password", text: $confirmation)
                            if newPassword.count < 12 && !newPassword.isEmpty { Text("Use at least 12 characters.").foregroundStyle(Theme.danger) }
                            AppleAuthorizationControl { payload in
                                guard newPassword.count >= 12, newPassword == confirmation else {
                                    throw APIError.http(status: 400, detail: "Passwords must match and contain at least 12 characters.")
                                }
                                guard let api = app.api else { throw APIError.unauthorized }
                                try await api.setPassword(newPassword, apple: payload)
                                newPassword = ""; confirmation = ""; await load()
                            }
                        }
                    } else {
                        Section {
                            Button("Unlink Apple", role: .destructive) { Task { await unlink() } }
                        } footer: { Text("Your password remains available after unlinking Apple.") }
                    }
                } else { ProgressView() }
                if let errorText { Section { Text(errorText).foregroundStyle(Theme.danger) } }
            }
            .navigationTitle("Sign in with Apple")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        do { status = try await app.api?.appleIdentityStatus(); errorText = nil }
        catch { errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    private func unlink() async {
        do { try await app.api?.unlinkApple(); await load() }
        catch { errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
}

private struct GoogleAccountSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var status: ExternalIdentityStatusDto?
    @State private var errorText: String?
    @State private var isBusy = false
    @State private var googleOAuth = GoogleOAuthSession()

    var body: some View {
        NavigationStack {
            Form {
                if let status {
                    Section {
                        Label(
                            status.linked ? "Google account linked" : "Google account not linked",
                            systemImage: status.linked ? "checkmark.shield" : "g.circle"
                        )
                        if status.linked {
                            if let email = status.email, !email.isEmpty {
                                Text(email).foregroundStyle(Theme.textSecondary)
                            } else if let name = status.displayName, !name.isEmpty {
                                Text(name).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    if status.linked {
                        Section {
                            Button("Unlink Google", role: .destructive) {
                                Task { await unlink() }
                            }
                            .disabled(isBusy || !status.canUnlink || !status.recentAuthentication)
                        } footer: {
                            if !status.canUnlink {
                                Text("Add another sign-in method (password, Apple, or passkey) before unlinking Google.")
                            } else if !status.recentAuthentication {
                                Text("Sign in again (within the last 5 minutes) to make this change.")
                            } else {
                                Text("Unlinking signs out other sessions and removes trusted devices.")
                            }
                        }
                    } else {
                        Section {
                            Button {
                                Task { await link() }
                            } label: {
                                if isBusy {
                                    ProgressView()
                                } else {
                                    Text("Link Google")
                                }
                            }
                            .disabled(isBusy || !status.recentAuthentication)
                        } footer: {
                            if !status.recentAuthentication {
                                Text("Sign in again (within the last 5 minutes), then tap Link Google.")
                            } else {
                                Text("Opens Google sign-in and attaches that account to your current Cheers session.")
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.danger) }
                }
            }
            .navigationTitle("Google account")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            status = try await app.api?.externalIdentityStatus(provider: "google")
            errorText = nil
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func link() async {
        isBusy = true
        defer { isBusy = false }
        do {
            guard let api = app.api else { throw APIError.unauthorized }
            let started = try await api.startExternalIdentityOAuthLink(
                provider: "google",
                deviceName: UIDevice.current.name
            )
            guard let url = URL(string: started.authorizationURL) else {
                throw APIError.http(status: 500, detail: "Invalid Google authorization URL.")
            }
            let callback = try await googleOAuth.authenticate(authorizationURL: url)
            guard let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
                throw APIError.http(status: 401, detail: "Google link did not return a callback.")
            }
            if let err = comps.queryItems?.first(where: { $0.name == "error" })?.value {
                throw APIError.http(status: 401, detail: err)
            }
            guard comps.queryItems?.first(where: { $0.name == "linked" })?.value == "google" else {
                throw APIError.http(status: 401, detail: "Google link did not complete.")
            }
            await load()
        } catch let oauthError as GoogleOAuthError {
            if case .cancelled = oauthError { return }
            errorText = oauthError.localizedDescription
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func unlink() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await app.api?.unlinkExternalIdentity(provider: "google")
            await load()
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private struct DeleteAccountSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var status: AppleIdentityStatus?
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently disables your account, revokes sessions and push notifications, anonymizes your profile, and disables bots you own. Shared workspaces are transferred or archived.")
                        .foregroundStyle(Theme.textBody)
                } header: { Text("Permanent action") }
                Section {
                    TextField("Type DELETE", text: $confirmation).textInputAutocapitalization(.characters)
                    if status?.hasPassword == true {
                        SecureField("Current password", text: $password)
                        Button("Delete account", role: .destructive) { Task { await deleteWithPassword() } }
                            .disabled(confirmation != "DELETE" || password.isEmpty || isDeleting)
                    } else if status != nil {
                        Text("Reauthenticate with Apple to confirm deletion.")
                        AppleAuthorizationControl { payload in
                            guard confirmation == "DELETE" else { throw APIError.http(status: 400, detail: "Type DELETE first.") }
                            guard let api = app.api else { throw APIError.unauthorized }
                            try await api.deleteAccount(currentPassword: nil, apple: payload)
                            app.clearSession(); dismiss()
                        }
                    }
                }
                if let errorText { Section { Text(errorText).foregroundStyle(Theme.danger) } }
            }
            .navigationTitle("Delete Account")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { status = try? await app.api?.appleIdentityStatus() }
        }
    }

    private func deleteWithPassword() async {
        guard let api = app.api else { return }
        isDeleting = true
        defer { isDeleting = false }
        do { try await api.deleteAccount(currentPassword: password, apple: nil); app.clearSession(); dismiss() }
        catch { errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }
}

private struct BlockedUsersSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var users: [BlockedUserDto] = []
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if users.isEmpty { Text("No blocked users").foregroundStyle(Theme.textSecondary) }
                ForEach(users) { user in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(user.displayName ?? user.username)
                            Text("@\(user.username)").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button("Unblock") { Task { await unblock(user) } }
                    }
                }
                if let errorText { Text(errorText).foregroundStyle(Theme.danger) }
            }
            .navigationTitle("Blocked Users")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }
    private func load() async { do { users = try await app.api?.blockedUsers() ?? [] } catch { errorText = error.localizedDescription } }
    private func unblock(_ user: BlockedUserDto) async { do { try await app.api?.unblockUser(user.userId); await load() } catch { errorText = error.localizedDescription } }
}

private struct AIConsentSettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var consents: [StoredAIConsent] = []
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if consents.isEmpty { Text("No external AI permissions granted").foregroundStyle(Theme.textSecondary) }
                ForEach(consents) { consent in
                    Section("#\(consent.channelName) · \(consent.botName)") {
                        LabeledContent("Provider", value: consent.providerName ?? "External service")
                        if let use = consent.dataUse { Text(use).foregroundStyle(Theme.textSecondary) }
                        if let raw = consent.privacyURL, let url = URL(string: raw) { Link("Privacy policy", destination: url) }
                        Button("Revoke permission", role: .destructive) { Task { await revoke(consent) } }
                    }
                }
                if let errorText { Text(errorText).foregroundStyle(Theme.danger) }
            }
            .navigationTitle("External AI Permissions")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await load() }
        }
    }
    private func load() async { do { consents = try await app.api?.storedAIConsents() ?? [] } catch { errorText = error.localizedDescription } }
    private func revoke(_ consent: StoredAIConsent) async { do { try await app.api?.revokeAIConsent(channelId: consent.channelId, botId: consent.botId); await load() } catch { errorText = error.localizedDescription } }
}

// MARK: - Workspace administration

struct WorkspaceAdminSheet: View {
    private enum Confirmation: Identifiable {
        case remove(WorkspaceMemberDto), leave, delete
        var id: String {
            switch self {
            case .remove(let member): return "remove-\(member.userId)"
            case .leave: return "leave"
            case .delete: return "delete"
            }
        }
    }

    @Environment(AppModel.self) private var app
    @Environment(ShellModel.self) private var shell
    @Environment(\.dismiss) private var dismiss

    let workspace: WorkspaceDto
    @State private var name: String
    @State private var members: [WorkspaceMemberDto] = []
    @State private var inviteIdentifier = ""
    @State private var inviteRole = "member"
    @State private var isBusy = false
    @State private var confirmation: Confirmation?
    @State private var errorText: String?

    init(workspace: WorkspaceDto) {
        self.workspace = workspace
        _name = State(initialValue: workspace.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workspace") {
                    TextField("Workspace name", text: $name)
                    Button("Save name") { Task { await saveName() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == workspace.name || isBusy)
                }

                Section {
                    TextField("Exact username or email", text: $inviteIdentifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Role", selection: $inviteRole) {
                        Text("Member").tag("member")
                        Text("Admin").tag("admin")
                        Text("Owner").tag("owner")
                    }
                    Button("Send invitation") { Task { await invite() } }
                        .disabled(inviteIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                } header: {
                    Text("Invite member")
                } footer: {
                    Text("Invitations remain pending until the recipient accepts. Only owners can grant the owner role.")
                }

                Section("Members") {
                    if members.isEmpty, errorText == nil { ProgressView() }
                    ForEach(members) { member in
                        HStack(spacing: 10) {
                            AvatarView(seedId: member.userId, name: member.name, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name)
                                Text("@\(member.username) · \(member.status)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if member.userId == app.session?.userId {
                                Text(member.role.capitalized).foregroundStyle(Theme.textSecondary)
                            } else {
                                Menu(member.role.capitalized) {
                                    ForEach(["member", "admin", "owner"], id: \.self) { role in
                                        Button(role.capitalized) { Task { await setRole(member, role: role) } }
                                    }
                                    Divider()
                                    Button("Remove", role: .destructive) { confirmation = .remove(member) }
                                }
                            }
                        }
                    }
                }

                Section("Danger zone") {
                    Button("Leave workspace", role: .destructive) { confirmation = .leave }
                    Button("Delete workspace", role: .destructive) { confirmation = .delete }
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(Theme.danger) }
                }
            }
            .disabled(isBusy)
            .navigationTitle("Workspace Admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await loadMembers() }
            .confirmationDialog(confirmationTitle, isPresented: Binding(
                get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }
            ), titleVisibility: .visible) {
                Button(confirmationButtonTitle, role: .destructive) { Task { await performConfirmation() } }
                Button("Cancel", role: .cancel) { confirmation = nil }
            } message: {
                Text(confirmationMessage)
            }
        }
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .remove(let member): return "Remove \(member.name)?"
        case .leave: return "Leave \(workspace.name)?"
        case .delete: return "Delete \(workspace.name)?"
        case nil: return "Confirm action"
        }
    }

    private var confirmationButtonTitle: String {
        switch confirmation {
        case .remove: return "Remove member"
        case .leave: return "Leave workspace"
        case .delete: return "Delete workspace"
        case nil: return "Confirm"
        }
    }

    private var confirmationMessage: String {
        switch confirmation {
        case .remove: return "The person loses access to workspace channels."
        case .leave: return "You lose access to this workspace. The last owner cannot leave."
        case .delete: return "The workspace and its contents are permanently removed."
        case nil: return ""
        }
    }

    private func loadMembers() async {
        guard let api = app.api else { return }
        do {
            members = try await api.listWorkspaceMembers(workspaceId: workspace.workspaceId)
            errorText = nil
        } catch { errorText = apiMessage(error) }
    }

    private func saveName() async {
        guard let api = app.api else { return }
        await run {
            _ = try await api.updateWorkspace(workspaceId: workspace.workspaceId, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            await shell.loadWorkspaces()
        }
    }

    private func invite() async {
        guard let api = app.api else { return }
        await run {
            try await api.inviteWorkspaceMember(
                workspaceId: workspace.workspaceId,
                identifier: inviteIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                role: inviteRole
            )
            inviteIdentifier = ""
            await loadMembers()
        }
    }

    private func setRole(_ member: WorkspaceMemberDto, role: String) async {
        guard let api = app.api else { return }
        await run {
            try await api.setWorkspaceMemberRole(workspaceId: workspace.workspaceId, userId: member.userId, role: role)
            await loadMembers()
        }
    }

    private func performConfirmation() async {
        guard let api = app.api, let action = confirmation else { return }
        confirmation = nil
        await run {
            switch action {
            case .remove(let member):
                try await api.removeWorkspaceMember(workspaceId: workspace.workspaceId, userId: member.userId)
                await loadMembers()
            case .leave:
                try await api.leaveWorkspace(workspaceId: workspace.workspaceId)
                shell.selectWorkspace(nil)
                await shell.loadWorkspaces()
                dismiss()
            case .delete:
                try await api.deleteWorkspace(workspaceId: workspace.workspaceId)
                shell.selectWorkspace(nil)
                await shell.loadWorkspaces()
                dismiss()
            }
        }
    }

    private func run(_ operation: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do { try await operation(); errorText = nil }
        catch { errorText = apiMessage(error) }
    }

    private func apiMessage(_ error: Error) -> String {
        (error as? APIError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Account sessions

private struct AccountSessionsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [AuthSessionSummary] = []
    @State private var revoking: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty, errorText == nil { ProgressView() }
                ForEach(sessions) { session in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label(session.deviceName ?? session.client.capitalized, systemImage: icon(for: session.client))
                                .font(.headline)
                            Spacer()
                            if session.current {
                                Text("This device").font(.caption).foregroundStyle(Theme.online)
                            }
                        }
                        Text("Last active \(relativeDate(session.lastSeenAt))")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        if !session.current {
                            Button("Revoke session", role: .destructive) { Task { await revoke(session) } }
                                .disabled(revoking != nil)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let errorText { Text(errorText).foregroundStyle(Theme.danger) }
            }
            .navigationTitle("Devices & Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        do { sessions = try await app.api?.listAuthSessions() ?? []; errorText = nil }
        catch { errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    private func revoke(_ session: AuthSessionSummary) async {
        guard let api = app.api else { return }
        revoking = session.id
        defer { revoking = nil }
        do { try await api.revokeAuthSession(sessionId: session.id); await load() }
        catch { errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription }
    }

    private func icon(for client: String) -> String {
        switch client { case "ios": return "iphone"; case "macos": return "desktopcomputer"; default: return "globe" }
    }

    private func relativeDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(.relative(presentation: .named))
    }
}
