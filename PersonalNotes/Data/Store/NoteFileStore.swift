import Foundation

/// On-disk representation of one note.
///
/// Notes are stored as a JSON file rather than a SQLite database: a personal notebook is small,
/// the whole list is already loaded for filtering, and a plain file keeps the app's data
/// inspectable and easy to back up. The repository protocol hides this choice, so a move to
/// SwiftData or GRDB later touches only this file.
struct NoteRecord: Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var description: String
    var createdAt: Date
    var updatedAt: Date
    var location: NoteLocation
    var colorId: String
    var kindId: String
    var fileRefs: [String]
    /// Hash of the note content, used to recognise a note that was already imported.
    var contentFingerprint: String

    init(note: Note, fingerprint: String) {
        self.id = note.id ?? UUID()
        self.title = note.title
        self.description = note.description
        self.createdAt = note.createdAt
        self.updatedAt = note.updatedAt
        self.location = note.location
        self.colorId = note.color.rawValue
        self.kindId = note.kind.rawValue
        self.fileRefs = note.fileRefs
        self.contentFingerprint = fingerprint
    }

    var asNote: Note {
        Note(
            id: id,
            title: title,
            description: description,
            createdAt: createdAt,
            updatedAt: updatedAt,
            location: location,
            color: NoteColor(id: colorId),
            kind: NoteKind(id: kindId),
            fileRefs: fileRefs
        )
    }
}

/// File-based persistence for the note list, plus the app-private attachments folder.
///
/// Writes are atomic (through `Data.write(options: .atomic)`), so an interrupted save cannot
/// truncate the notebook.
final class NoteFileStore {
    private let rootDirectory: URL
    private let files = FileManager.default

    init(rootDirectory: URL? = nil) {
        let base = rootDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonalNotes", isDirectory: true)
        self.rootDirectory = base
        try? files.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
    }

    private var notesFile: URL { rootDirectory.appendingPathComponent("notes.json") }

    var attachmentsDirectory: URL { rootDirectory.appendingPathComponent("attachments", isDirectory: true) }

    var exportsDirectory: URL { rootDirectory.appendingPathComponent("exports", isDirectory: true) }

    // MARK: - Notes

    func loadNotes() -> [NoteRecord] {
        guard let data = try? Data(contentsOf: notesFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([NoteRecord].self, from: data)) ?? []
    }

    func saveNotes(_ records: [NoteRecord]) throws {
        try files.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: notesFile, options: .atomic)
    }

    // MARK: - Attachments

    /// Records live in the cache until the note is saved, so an abandoned draft leaves nothing
    /// behind in permanent storage.
    func newRecordingURL() throws -> URL {
        let directory = files.temporaryDirectory.appendingPathComponent("PersonalNotes", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("voice-\(Int(Date().timeIntervalSince1970 * 1000)).m4a")
    }

    func attachmentURL(_ fileRef: String) -> URL? {
        guard !fileRef.isEmpty, !fileRef.contains("/"), !fileRef.contains("..") else { return nil }
        return attachmentsDirectory.appendingPathComponent(fileRef)
    }

    func exists(_ fileRef: String) -> Bool {
        guard let url = attachmentURL(fileRef) else { return false }
        return files.fileExists(atPath: url.path)
    }

    /// Moves a freshly recorded file into permanent storage and returns its file reference.
    @discardableResult
    func persistAttachment(at temporaryURL: URL) throws -> String {
        let name = temporaryURL.lastPathComponent
        guard let target = attachmentURL(name) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        if temporaryURL.standardizedFileURL == target.standardizedFileURL {
            return name
        }
        if files.fileExists(atPath: target.path) {
            try? files.removeItem(at: target)
        }
        try files.moveItem(at: temporaryURL, to: target)
        return name
    }

    func writeAttachment(name: String, data: Data) throws -> String {
        try files.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        let safe = name.isEmpty ? "attachment" : name
        guard let url = attachmentURL(safe) else { throw CocoaError(.fileWriteInvalidFileName) }
        try data.write(to: url, options: .atomic)
        return safe
    }

    func deleteAttachments(_ fileRefs: [String]) {
        for ref in fileRefs {
            guard let url = attachmentURL(ref) else { continue }
            try? files.removeItem(at: url)
        }
    }

    /// Copies an attachment into the exports directory so it can be handed to another app.
    func copyForSharing(_ fileRef: String) -> URL? {
        guard let source = attachmentURL(fileRef), files.fileExists(atPath: source.path) else { return nil }
        try? files.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
        let target = exportsDirectory.appendingPathComponent(source.lastPathComponent)
        try? files.removeItem(at: target)
        do {
            try files.copyItem(at: source, to: target)
            return target
        } catch {
            return nil
        }
    }
}
