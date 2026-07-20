import Foundation
import UIKit

/// Retains one ChatModel per channel across channel switches — the iOS
/// counterpart of the web client's chatCache. Re-entering a cached channel
/// renders its in-memory history instantly; the model then heals anything
/// missed while detached via the existing since_seq catch-up, instead of
/// paying a full cold reload (50 messages + members) on every entry.
/// LRU-bounded so a long session doesn't pin every visited channel's history.
@MainActor
final class ChatModelStore {
    private var models: [String: ChatModel] = [:]
    /// LRU order, most recently used last. The open channel is always the most
    /// recently touched entry, so it can never be the eviction candidate.
    private var order: [String] = []
    private let capacity = 12

    init() {
        // Platform convention: an in-memory cache sheds under memory pressure.
        // Safe to be aggressive — evicted history reloads from the SwiftData
        // cache (MessageStore) without a network round-trip.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.shedAllButCurrent()
            }
        }
    }

    /// Memory warning: drop every cached model except the open channel's (the
    /// most recently touched entry — the one a view may be holding right now).
    private func shedAllButCurrent() {
        guard let current = order.last else { return }
        models = models.filter { $0.key == current }
        order = [current]
    }

    func model(for channel: ChannelDto) -> ChatModel {
        if let existing = models[channel.channelId] {
            existing.refresh(channel: channel)
            touch(channel.channelId)
            return existing
        }
        let model = ChatModel(channel: channel)
        models[channel.channelId] = model
        touch(channel.channelId)
        while order.count > capacity, let evicted = order.first {
            order.removeFirst()
            models.removeValue(forKey: evicted)
        }
        return model
    }

    /// Sign-out: cached history belongs to the old session.
    func removeAll() {
        models.removeAll()
        order.removeAll()
    }

    private func touch(_ channelId: String) {
        order.removeAll { $0 == channelId }
        order.append(channelId)
    }
}
