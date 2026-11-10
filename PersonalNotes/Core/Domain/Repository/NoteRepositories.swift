import Foundation

/// Storage port for notes. The domain only knows this protocol; JSON files, the keychain of
/// options (SQLite, CloudKit) all live behind it in the data layer.
protocol NoteRepository: AnyObject, Sendable {
    /// Emits the full list after every change, starting with the current contents.
    func observeNotes() -> AsyncStream<[Note]>

    func note(id: UUID) async -> Note?

    func save(_ note: Note) async throws -> UUID

    func delete(id: UUID) async throws

    /// Reads a `.pnote` document shared by another user and stores it locally.
    func importNote(data: Data, source: NoteImportSource) async -> NoteImportResult

    /// Reads a note without storing it.
    func decodeNote(data: Data) throws -> Note
}

/// Result of exporting one note to something the user can send.
struct ExportedNote: Sendable {
    let fileURL: URL
    let fileName: String
    let mimeType: String
    /// Self-contained link that carries the whole note.
    let shareLink: String
}

/// Port for handing a note to another user: the `.pnote` file, the deep link, and sharing.
protocol NoteShareRepository: Sendable {
    func export(_ note: Note) async throws -> ExportedNote

    func shareLink(for note: Note) -> String

    /// Copies an app-private attachment into a shareable location.
    func prepareAttachment(fileRef: String) async -> URL?
}

/// "Where am I right now", behind a protocol so the UI never touches CoreLocation directly.
protocol LocationProvider: AnyObject, Sendable {
    func currentLocation() async throws -> NoteLocation
}
