import Foundation

/// Everything the notes list needs, already filtered and sorted. Mirrors Android's
/// `ObserveNotesUseCase`.
struct ObserveNotesUseCase {
    private let repository: NoteRepository

    init(repository: NoteRepository) {
        self.repository = repository
    }

    func stream(filter: NoteFilter) -> AsyncStream<[Note]> {
        let upstream = repository.observeNotes()
        return AsyncStream { continuation in
            let task = Task {
                for await notes in upstream {
                    continuation.yield(Self.apply(notes, filter: filter))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Pure, so it is unit tested without any storage.
    static func apply(_ notes: [Note], filter: NoteFilter) -> [Note] {
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = notes.filter { note in
            (filter.color == nil || note.color == filter.color) &&
                (query.isEmpty || matches(note, query: query))
        }

        switch filter.sort {
        case .newest: return filtered.sorted { $0.updatedAt > $1.updatedAt }
        case .oldest: return filtered.sorted { $0.updatedAt < $1.updatedAt }
        case .title: return filtered.sorted { $0.displayTitle.lowercased() < $1.displayTitle.lowercased() }
        case .color: return filtered.sorted {
            let left = NoteColor.allCases.firstIndex(of: $0.color) ?? 0
            let right = NoteColor.allCases.firstIndex(of: $1.color) ?? 0
            return left == right ? $0.updatedAt > $1.updatedAt : left < right
        }
        }
    }

    private static func matches(_ note: Note, query: String) -> Bool {
        note.title.localizedCaseInsensitiveContains(query) ||
            note.description.localizedCaseInsensitiveContains(query) ||
            note.location.label.localizedCaseInsensitiveContains(query)
    }
}

/// Loads a single note for the editor.
struct GetNoteUseCase {
    private let repository: NoteRepository

    init(repository: NoteRepository) {
        self.repository = repository
    }

    func callAsFunction(id: UUID?) async -> Note? {
        guard let id else { return nil }
        return await repository.note(id: id)
    }
}

/// Validates and persists a note. Blank notes are rejected so the list never fills with empty
/// cards after an accidental back swipe.
struct UpsertNoteUseCase {
    enum Outcome: Equatable {
        case saved(UUID)
        case nothingToSave
    }

    private let repository: NoteRepository
    private let now: () -> Date

    init(repository: NoteRepository, now: @escaping () -> Date = { .now }) {
        self.repository = repository
        self.now = now
    }

    func callAsFunction(_ draft: NoteDraft) async throws -> Outcome {
        if !draft.hasContent {
            return .nothingToSave
        }
        let timestamp = now()
        let note = Note(
            id: draft.id,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: draft.createdAt,
            updatedAt: timestamp,
            location: draft.location,
            color: draft.color,
            kind: Self.resolveKind(draft),
            fileRefs: draft.fileRefs
        )
        return .saved(try await repository.save(note))
    }

    /// Typed text plus a recording is "mixed"; a recording alone is "spoken"; a preference the
    /// user already expressed is respected.
    private static func resolveKind(_ draft: NoteDraft) -> NoteKind {
        if draft.kind == .mixed { return .mixed }
        if !draft.fileRefs.isEmpty { return draft.description.isEmpty ? .spoken : .mixed }
        return .typed
    }
}

private extension NoteDraft {
    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !fileRefs.isEmpty
    }
}

struct DeleteNoteUseCase {
    private let repository: NoteRepository

    init(repository: NoteRepository) {
        self.repository = repository
    }

    func callAsFunction(id: UUID) async throws {
        try await repository.delete(id: id)
    }
}

/// Ingests a note another user shared (file or deep link).
struct ImportNoteUseCase {
    private let repository: NoteRepository

    init(repository: NoteRepository) {
        self.repository = repository
    }

    func callAsFunction(data: Data, source: NoteImportSource = .file) async -> NoteImportResult {
        await repository.importNote(data: data, source: source)
    }
}

/// Turns a note into a shareable `.pnote` file plus a self-contained deep link.
struct ExportNoteUseCase {
    private let repository: NoteShareRepository

    init(repository: NoteShareRepository) {
        self.repository = repository
    }

    func callAsFunction(note: Note) async throws -> ExportedNote {
        try await repository.export(note)
    }
}

/// Builds only the link, for "copy link" style actions.
struct BuildNoteLinkUseCase {
    private let repository: NoteShareRepository

    init(repository: NoteShareRepository) {
        self.repository = repository
    }

    func callAsFunction(note: Note) -> String {
        repository.shareLink(for: note)
    }
}
