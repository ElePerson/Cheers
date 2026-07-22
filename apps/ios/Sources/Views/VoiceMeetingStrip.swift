import SwiftUI

/// Compact voice header: the normal chat timeline and composer remain intact.
struct VoiceMeetingStrip: View {
    @Bindable var voice: VoiceRoomModel
    let canManageTranscription: Bool
    @State private var controls = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: voice.isConnected ? "waveform" : "waveform.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(voice.isConnected ? Theme.online : Theme.link)
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.isConnected ? "Voice meeting in progress" : "Voice meeting")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(voice.isConnected ? "Controls" : "Join") {
                    if voice.isConnected { controls = true } else { Task { await voice.join() } }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 13).frame(minHeight: 34)
                .background(Theme.accent, in: Capsule())
                .disabled(voice.isJoining)
            }
            if let latest = voice.transcripts.last, !latest.text.isEmpty {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    Text(latest.text).font(.system(size: 12)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(9).background(Theme.bgRaised, in: RoundedRectangle(cornerRadius: 9))
            }
            if let error = voice.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.bgSurface)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.border) }
        .sheet(isPresented: $controls) {
            VoiceControlsSheet(voice: voice, canManageTranscription: canManageTranscription)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var detail: String {
        if voice.isJoining { return "Joining…" }
        if voice.isConnected { return "\(max(1, voice.participantNames.count)) participant\(voice.participantNames.count == 1 ? "" : "s") · \(voice.transcriptionStatus == "active" ? "Captions on" : "Captions off")" }
        return "Join to speak and follow live captions"
    }
}

private struct VoiceControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var voice: VoiceRoomModel
    let canManageTranscription: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Voice meeting").font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.textPrimary)
            if voice.participantNames.isEmpty { Text("Only you are here").foregroundStyle(Theme.textSecondary) }
            else { Text(voice.participantNames.joined(separator: ", ")).font(.system(size: 14)).foregroundStyle(Theme.textSecondary) }
            Button { Task { await voice.toggleMicrophone() } } label: {
                Label(voice.micEnabled ? "Mute microphone" : "Unmute microphone", systemImage: voice.micEnabled ? "mic.fill" : "mic.slash.fill")
                    .frame(maxWidth: .infinity).frame(minHeight: 46).background(Theme.bgRaised, in: RoundedRectangle(cornerRadius: 12))
            }.disabled(!voice.canPublish)
            if !voice.canPublish {
                Button { Task { await voice.acceptConsent() } } label: {
                    Label("Allow transcription and speak", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity).frame(minHeight: 46).background(Theme.accent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white)
                }
            }
            if canManageTranscription {
                Button {
                    Task { await voice.setTranscription(voice.transcriptionStatus != "active") }
                } label: {
                    Label(
                        voice.transcriptionStatus == "active" ? "Turn off live captions" : "Turn on live captions",
                        systemImage: "captions.bubble"
                    )
                    .frame(maxWidth: .infinity).frame(minHeight: 46)
                    .background(Theme.bgRaised, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            Button(role: .destructive) { Task { await voice.leave(); dismiss() } } label: {
                Label("Leave meeting", systemImage: "phone.down.fill").frame(maxWidth: .infinity).frame(minHeight: 46)
            }
            Spacer()
        }.padding(20).background(Theme.bgSurface)
    }
}
