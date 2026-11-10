import Foundation

/// Produces the `.pnote` file and the self-contained deep link for a note.
///
/// Files are written into the app's exports directory and shared through `UIActivityViewController`
/// (or the share sheet's file representation), which gives the receiver the same document the
/// Android app produces.
final class FileNoteShareRepository: NoteShareRepository, @unchecked Sendable {
    static let urlScheme = "personalnotes"
    static let linkHost = "note"
    static let fileExtension = "pnote"

    private let store: NoteFileStore
    private let maxInlineAttachmentBytes: Int

    init(store: NoteFileStore, maxInlineAttachmentBytes: Int = 2 * 1024 * 1024) {
        self.store = store
        self.maxInlineAttachmentBytes = maxInlineAttachmentBytes
    }

    func export(_ note: Note) async throws -> ExportedNote {
        let payload = NotePayload.from(note, attachments: inlineAttachments(for: note))
        let data = try NotePayloadCodec.encodeToFileBytes(payload)

        var directory = store.exportsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directory = directory.appendingPathComponent(fileName(for: note))
        try data.write(to: directory, options: .atomic)

        return ExportedNote(
            fileURL: directory,
            fileName: directory.lastPathComponent,
            mimeType: NotePayload.mimeType,
            shareLink: shareLink(for: note)
        )
    }

    func shareLink(for note: Note) -> String {
        // The link carries the note itself, so the receiver does not need the file.
        let token = (try? NotePayloadCodec.encodeToLinkToken(NotePayload.from(note))) ?? ""
        return "\(Self.urlScheme)://\(Self.linkHost)/\(NotePayloadCodec.linkSegment)/\(token)"
    }

    func prepareAttachment(fileRef: String) async -> URL? {
        store.copyForSharing(fileRef)
    }

    /// Recordings under the inline limit travel inside the file, so a single `.pnote` really is
    /// the whole note.
    private func inlineAttachments(for note: Note) -> [NoteAttachmentPayload] {
        note.fileRefs.compactMap { ref in
            guard let url = store.attachmentURL(ref),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0, size <= maxInlineAttachmentBytes,
                  let data = try? Data(contentsOf: url) else { return nil }
            return NoteAttachmentPayload(
                name: ref,
                mimeType: mimeType(for: ref),
                data: NotePayloadCodec.base64UrlEncode(data)
            )
        }
    }

    private func fileName(for note: Note) -> String {
        let slug = note.title
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .prefix(32)
        let base = slug.isEmpty ? "note" : String(slug)
        return "\(base)-\(note.id?.uuidString.prefix(8) ?? "new").\(Self.fileExtension)"
    }

    private func mimeType(for fileRef: String) -> String {
        switch (fileRef as NSString).pathExtension.lowercased() {
        case "m4a", "aac", "mp4": return "audio/mp4"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        default: return "application/octet-stream"
        }
    }
}
