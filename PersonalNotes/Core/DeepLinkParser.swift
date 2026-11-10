import Foundation

/// Parses every way a note can arrive from another user of the app, so the UI reacts to one
/// sealed type. Mirrors the Android implementation's accepted shapes:
///
/// - `personalnotes://note/d/<token>` - the link carries the note itself
/// - `personalnotes://note/<uuid>`    - a note already stored on this device
/// - `https://personalnotes.app/note/...` - the same, as a universal-link style URL
/// - a `.pnote` document opened from Mail, Messages or Files
enum DeepLinkParser {
    enum Incoming: Equatable {
        case localNote(UUID)
        case embeddedNote(token: String)
        case noteDocument(URL)
    }

    static func parse(_ url: URL) -> Incoming? {
        if url.isFileURL || isNoteDocument(url) {
            return .noteDocument(url)
        }

        let segments = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        // personalnotes://note/d/<token>: for a custom scheme the host is "note" and the path is
        // "/d/<token>", so both are considered.
        var tail = segments
        if let host = url.host, !host.isEmpty {
            tail.insert(host, at: 0)
        }
        if let noteIndex = tail.firstIndex(where: { $0.caseInsensitiveCompare("note") == .orderedSame }) {
            tail = Array(tail[(noteIndex + 1)...])
        }

        if tail.first?.caseInsensitiveCompare(NotePayloadCodec.linkSegment) == .orderedSame {
            guard let token = tail.dropFirst().first, !token.isEmpty else { return nil }
            return .embeddedNote(token: token)
        }

        if let candidate = tail.first, let id = UUID(uuidString: candidate) {
            return .localNote(id)
        }

        // personalnotes://import?d=<token>
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "d" })?.value,
           !token.isEmpty {
            return .embeddedNote(token: token)
        }

        // A long opaque segment is treated as an embedded payload; share sheets sometimes echo
        // only part of the URL, so the whole path is considered rather than just its first part.
        if let candidate = tail.last(where: { $0.count > 40 }) {
            return .embeddedNote(token: candidate)
        }
        return nil
    }

    static func isNoteDocument(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare(FileNoteShareRepository.fileExtension) == .orderedSame
    }
}
