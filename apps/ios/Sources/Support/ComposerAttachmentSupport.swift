import Foundation

/// Shared helpers for the composer attach → upload → send path.
/// The gateway rejects empty message `content`, so attachment-only sends must
/// fall back to filenames (same behavior as the web MessageComposer).
enum ComposerAttachmentSupport {
    /// Soft client ceiling before we load the whole file into memory. The
    /// gateway stores `size_bytes` as i32; this is a UX guard, not the protocol max.
    static let maxUploadBytes = 100 * 1024 * 1024

    /// Non-empty body for `POST /messages`. Returns `nil` when there is neither
    /// typed text nor at least one filename to fall back on.
    static func messageContent(draft: String, filenames: [String]) -> String? {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let names = filenames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    /// Read bytes from a document-picker / Files URL, including security-scoped
    /// and iCloud-coordinated paths. Throws a localized error when empty/unreadable.
    static func readUploadData(from url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var data: Data?
        var coordError: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { readURL in
            data = try? Data(contentsOf: readURL, options: [.mappedIfSafe])
        }
        if let coordError { throw coordError }
        guard let data, !data.isEmpty else {
            throw ComposerAttachmentError.unreadable
        }
        if data.count > maxUploadBytes {
            throw ComposerAttachmentError.tooLarge(maxBytes: maxUploadBytes)
        }
        return data
    }
}

enum ComposerAttachmentError: LocalizedError {
    case unreadable
    case tooLarge(maxBytes: Int)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Couldn't read that file. Try exporting a local copy and uploading again."
        case .tooLarge(let maxBytes):
            let mb = maxBytes / (1024 * 1024)
            return "This file is larger than \(mb) MB, which this app won't upload."
        case .cancelled:
            return nil
        }
    }
}
