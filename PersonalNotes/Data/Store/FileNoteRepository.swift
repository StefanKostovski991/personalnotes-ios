import Foundation

/// JSON-file implementation of ``NoteRepository``.
///
/// Importing is idempotent: the incoming payload is fingerprinted on content, and a note with the
/// same fingerprint is reported as `.alreadyExists` instead of being duplicated - the same rule
/// the Android app applies, so a note cannot be duplicated by bouncing it between platforms.
@MainActor
final class FileNoteRepository: NoteRepository {
    private let store: NoteFileStore
    private var records: [NoteRecord]
    private var continuations: [UUID: AsyncStream<[Note]>.Continuation] = [:]

    init(store: NoteFileStore) {
        self.store = store
        self.records = store.loadNotes()
    }

    // MARK: - Observation

    func observeNotes() -> AsyncStream<[Note]> {
        AsyncStream { continuation in
            let id = UUID()
            Task { @MainActor in self.register(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { @MainActor in self.unregister(id: id) }
            }
        }
    }

    private func register(id: UUID, continuation: AsyncStream<[Note]>.Continuation) {
        continuations[id] = continuation
        continuation.yield(notesSnapshot)
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func broadcast() {
        let snapshot = notesSnapshot
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private var notesSnapshot: [Note] {
        records.map(\.asNote).sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Reads

    func note(id: UUID) async -> Note? {
        records.first { $0.id == id }?.asNote
    }

    // MARK: - Writes

    func save(_ note: Note) async throws -> UUID {
        // A recording may still live in the temporary directory; it becomes permanent only once
        // its note is saved.
        var fileRefs: [String] = []
        for ref in note.fileRefs {
            if store.exists(ref) {
                fileRefs.append(ref)
            } else if let temp = temporaryURL(for: ref) {
                fileRefs.append(try store.persistAttachment(at: temp))
            } else {
                fileRefs.append(ref)
            }
        }

        var stored = note
        stored.fileRefs = fileRefs
        let payload = NotePayload.from(stored)
        let fingerprint = NotePayloadCodec.fingerprint(payload)
        let record = NoteRecord(note: stored, fingerprint: fingerprint)

        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        try store.saveNotes(records)
        broadcast()
        return record.id
    }

    func delete(id: UUID) async throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records.remove(at: index)
        store.deleteAttachments(record.fileRefs)
        try store.saveNotes(records)
        broadcast()
    }

    // MARK: - Import

    func importNote(data: Data, source: NoteImportSource) async -> NoteImportResult {
        let payload: NotePayload
        do {
            payload = try NotePayloadCodec.parse(data)
        } catch {
            return .failed(error.localizedDescription)
        }

        let fingerprint = NotePayloadCodec.fingerprint(payload)
        if let existing = records.first(where: { $0.contentFingerprint == fingerprint }) {
            return .alreadyExists(existing.asNote)
        }

        let fileRefs = payload.attachments.compactMap { attachment -> String? in
            guard let encoded = attachment.data,
                  let bytes = try? NotePayloadCodec.base64UrlDecode(encoded) else { return nil }
            return try? store.writeAttachment(name: attachment.name, data: bytes)
        }

        let imported = payload.toNote(id: UUID(), fileRefs: fileRefs)
        let record = NoteRecord(note: imported, fingerprint: fingerprint)
        records.append(record)
        do {
            try store.saveNotes(records)
        } catch {
            records.removeAll { $0.id == record.id }
            return .failed(error.localizedDescription)
        }
        broadcast()
        return .imported(record.asNote)
    }

    func decodeNote(data: Data) throws -> Note {
        try NotePayloadCodec.parse(data).toNote()
    }

    // MARK: - Helpers

    private func temporaryURL(for ref: String) -> URL? {
        guard !store.exists(ref) else { return nil }
        let candidate = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalNotes", isDirectory: true)
            .appendingPathComponent(ref)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}
