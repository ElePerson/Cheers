import Foundation
import SwiftData

/// Offline-first message cache (SwiftData): the newest window of every visited
/// channel persists across launches, so a cold app start renders history
/// instantly and then refreshes over the network — the Telegram model. This is
/// a CACHE, not a source of record: the gateway stays authoritative, rows are
/// upserted from REST/WS data, trimmed per channel, and wiped on sign-out.
///
/// Messages are stored as their full DTO JSON plus the few fields queries
/// need (channel, seq). The blob keeps the store schema-stable while the DTO
/// evolves; a row that no longer decodes is simply skipped and re-fetched.

@Model
final class CachedMessage {
    @Attribute(.unique) var msgId: String
    var channelId: String
    var channelSeq: Int64
    var payload: Data

    init(msgId: String, channelId: String, channelSeq: Int64, payload: Data) {
        self.msgId = msgId
        self.channelId = channelId
        self.channelSeq = channelSeq
        self.payload = payload
    }
}

@Model
final class CachedChannelState {
    @Attribute(.unique) var channelId: String
    /// Whether older history exists server-side beyond the cached window —
    /// restored so upward pagination works straight off a cold start.
    var hasMoreBefore: Bool

    init(channelId: String, hasMoreBefore: Bool) {
        self.channelId = channelId
        self.hasMoreBefore = hasMoreBefore
    }
}

@MainActor
final class MessageStore {
    /// Disk keeps a deeper window than the in-memory trim (ChatModel keeps 100
    /// on detach) so a relaunch still has scrollback before paging the server.
    private static let keepPerChannel = 200

    /// nil when the container fails to open (e.g. disk full) — every call then
    /// degrades to a no-op and the app just runs network-only.
    private let container: ModelContainer?

    /// `url` overrides the store location (tests use a temp file); the app
    /// uses the platform default.
    init(url: URL? = nil) {
        if let url {
            let config = ModelConfiguration(url: url)
            container = try? ModelContainer(
                for: CachedMessage.self, CachedChannelState.self,
                configurations: config
            )
        } else {
            container = try? ModelContainer(for: CachedMessage.self, CachedChannelState.self)
        }
    }

    func load(channelId: String) -> (messages: [MessageDto], hasMoreBefore: Bool)? {
        guard let context = container?.mainContext else { return nil }
        let descriptor = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { $0.channelId == channelId },
            sortBy: [SortDescriptor(\.channelSeq, order: .forward)]
        )
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return nil }
        let decoder = JSONDecoder()
        let messages = rows.compactMap { try? decoder.decode(MessageDto.self, from: $0.payload) }
        guard !messages.isEmpty else { return nil }
        return (messages, channelState(channelId, in: context)?.hasMoreBefore ?? true)
    }

    /// Upserts the finalized rows of `messages` (channel_seq stamped; in-flight
    /// placeholders re-arrive via catch-up) and trims the channel to the newest
    /// window. Trimming means older history still exists server-side, so the
    /// stored hasMoreBefore flips on with it.
    func save(channelId: String, messages: [MessageDto], hasMoreBefore: Bool) {
        guard let context = container?.mainContext else { return }
        let encoder = JSONEncoder()
        // Rows dropped by this window still exist server-side — that alone
        // means "more before" for the cached view of this channel.
        var trimmed = messages.count > Self.keepPerChannel
        for message in messages.suffix(Self.keepPerChannel) {
            guard let seq = message.channelSeq,
                  let payload = try? encoder.encode(message) else { continue }
            context.insert(
                CachedMessage(msgId: message.msgId, channelId: channelId, channelSeq: seq, payload: payload)
            )
        }

        // Persist the upserts BEFORE trimming: SwiftData does not apply
        // fetchOffset/limit windows reliably to pending (unsaved) objects — a
        // pre-save trim fetch sees every fresh insert as "overflow" and deletes
        // the batch it was meant to keep. Trim against persisted rows, and slice
        // in code rather than trusting fetchOffset at all.
        try? context.save()

        let newestFirst = FetchDescriptor<CachedMessage>(
            predicate: #Predicate { $0.channelId == channelId },
            sortBy: [SortDescriptor(\.channelSeq, order: .reverse)]
        )
        if let rows = try? context.fetch(newestFirst), rows.count > Self.keepPerChannel {
            trimmed = true
            for row in rows.dropFirst(Self.keepPerChannel) {
                context.delete(row)
            }
        }

        let more = hasMoreBefore || trimmed
        if let state = channelState(channelId, in: context) {
            state.hasMoreBefore = more
        } else {
            context.insert(CachedChannelState(channelId: channelId, hasMoreBefore: more))
        }
        try? context.save()
    }

    /// A deleted message must not resurrect from disk on the next launch.
    func delete(msgId: String) {
        guard let context = container?.mainContext else { return }
        try? context.delete(model: CachedMessage.self, where: #Predicate { $0.msgId == msgId })
        try? context.save()
    }

    /// Sign-out: cached history belongs to the old session.
    func removeAll() {
        guard let context = container?.mainContext else { return }
        try? context.delete(model: CachedMessage.self)
        try? context.delete(model: CachedChannelState.self)
        try? context.save()
    }

    private func channelState(_ channelId: String, in context: ModelContext) -> CachedChannelState? {
        var descriptor = FetchDescriptor<CachedChannelState>(
            predicate: #Predicate { $0.channelId == channelId }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
