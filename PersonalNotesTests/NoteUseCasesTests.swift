import XCTest
@testable import PersonalNotes

/// The use cases are pure, so they are tested without any storage or simulator state.
final class NoteUseCasesTests: XCTestCase {

    private func note(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        color: NoteColor = .default,
        updatedAt: TimeInterval,
        location: NoteLocation = .empty
    ) -> Note {
        Note(
            id: id,
            title: title,
            description: description,
            createdAt: Date(timeIntervalSince1970: updatedAt),
            updatedAt: Date(timeIntervalSince1970: updatedAt),
            location: location,
            color: color
        )
    }

    private lazy var alpha = note(title: "Alpha", description: "first note", updatedAt: 10)
    private lazy var bravo = note(title: "Bravo", description: "second note about coffee", color: .amber, updatedAt: 30)
    private lazy var charlie = note(
        title: "Charlie",
        description: "third",
        color: .amber,
        updatedAt: 20,
        location: NoteLocation(label: "Vienna")
    )

    private var all: [Note] { [alpha, bravo, charlie] }

    func testDefaultSortIsNewestFirst() {
        let result = ObserveNotesUseCase.apply(all, filter: .all)
        XCTAssertEqual(result.map(\.title), ["Bravo", "Charlie", "Alpha"])
    }

    func testOldestSortReversesOrder() {
        var filter = NoteFilter()
        filter.sort = .oldest
        XCTAssertEqual(ObserveNotesUseCase.apply(all, filter: filter).map(\.title), ["Alpha", "Charlie", "Bravo"])
    }

    func testTitleSort() {
        var filter = NoteFilter()
        filter.sort = .title
        XCTAssertEqual(ObserveNotesUseCase.apply(all, filter: filter).map(\.title), ["Alpha", "Bravo", "Charlie"])
    }

    func testQueryMatchesTitleDescriptionAndPlace() {
        var filter = NoteFilter()
        filter.query = "coffee"
        XCTAssertEqual(ObserveNotesUseCase.apply(all, filter: filter).map(\.title), ["Bravo"])

        filter.query = "vienna"
        XCTAssertEqual(ObserveNotesUseCase.apply(all, filter: filter).map(\.title), ["Charlie"])

        filter.query = "ALPHA"
        XCTAssertEqual(ObserveNotesUseCase.apply(all, filter: filter).map(\.title), ["Alpha"])
    }

    func testColourFilterCombinesWithQuery() {
        var filter = NoteFilter()
        filter.color = .amber
        XCTAssertEqual(ObserveNotesUseCase.apply(all, filter: filter).map(\.title), ["Bravo", "Charlie"])

        filter.query = "third"
        XCTAssertEqual(ObserveNotesUseCase.apply(all, filter: filter).map(\.title), ["Charlie"])
    }

    func testEmptyDraftIsRejected() async throws {
        let repository = InMemoryNoteRepository()
        let useCase = UpsertNoteUseCase(repository: repository)
        let outcome = try await useCase(NoteDraft())
        XCTAssertEqual(outcome, .nothingToSave)
    }

    func testSavingTrimsAndStamps() async throws {
        let repository = InMemoryNoteRepository()
        let timestamp = Date(timeIntervalSince1970: 5_000)
        let useCase = UpsertNoteUseCase(repository: repository, now: { timestamp })

        let outcome = try await useCase(NoteDraft(title: "  Padded  ", description: "  body  "))
        guard case .saved(let id) = outcome else { return XCTFail("expected a saved note") }

        let saved = await repository.note(id: id)
        XCTAssertEqual(saved?.title, "Padded")
        XCTAssertEqual(saved?.description, "body")
        XCTAssertEqual(saved?.updatedAt, timestamp)
    }

    func testRecordingWithoutTextIsStillSaved() async throws {
        let repository = InMemoryNoteRepository()
        let useCase = UpsertNoteUseCase(repository: repository)
        let outcome = try await useCase(NoteDraft(fileRefs: ["voice-1.m4a"]))
        guard case .saved = outcome else { return XCTFail("a recording alone is a valid note") }
    }

    func testKindIsDerivedFromInputs() async throws {
        let repository = InMemoryNoteRepository()
        let useCase = UpsertNoteUseCase(repository: repository)

        let spoken = try await useCase(NoteDraft(description: "", fileRefs: ["voice.m4a"]))
        guard case .saved(let spokenID) = spoken else { return XCTFail() }
        let spokenNote = await repository.note(id: spokenID)
        XCTAssertEqual(spokenNote?.kind, .spoken)

        let mixed = try await useCase(NoteDraft(description: "words", fileRefs: ["voice.m4a"]))
        guard case .saved(let mixedID) = mixed else { return XCTFail() }
        let mixedNote = await repository.note(id: mixedID)
        XCTAssertEqual(mixedNote?.kind, .mixed)
    }

    func testExistingNoteKeepsCreationTime() async throws {
        let repository = InMemoryNoteRepository()
        let existing = Note(
            id: UUID(),
            title: "Alpha",
            createdAt: Date(timeIntervalSince1970: 111),
            updatedAt: Date(timeIntervalSince1970: 111)
        )
        await repository.insert(existing)

        let useCase = UpsertNoteUseCase(repository: repository, now: { Date(timeIntervalSince1970: 9_000) })
        let outcome = try await useCase(
            NoteDraft(id: existing.id, title: "Alpha", createdAt: Date(timeIntervalSince1970: 111))
        )
        guard case .saved(let id) = outcome else { return XCTFail() }
        let saved = await repository.note(id: id)
        XCTAssertEqual(saved?.createdAt, Date(timeIntervalSince1970: 111))
        XCTAssertEqual(saved?.updatedAt, Date(timeIntervalSince1970: 9_000))
    }
}

/// In-memory replacement for the file repository.
private final class InMemoryNoteRepository: NoteRepository {
    private var notes: [UUID: Note] = [:]

    func observeNotes() -> AsyncStream<[Note]> {
        let snapshot = Array(notes.values)
        return AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }

    func note(id: UUID) async -> Note? { notes[id] }

    func save(_ note: Note) async throws -> UUID {
        let id = note.id ?? UUID()
        var stored = note
        stored.id = id
        notes[id] = stored
        return id
    }

    func insert(_ note: Note) {
        if let id = note.id { notes[id] = note }
    }

    func delete(id: UUID) async throws { notes.removeValue(forKey: id) }

    func importNote(data: Data, source: NoteImportSource) async -> NoteImportResult {
        .failed("not used in these tests")
    }

    func decodeNote(data: Data) throws -> Note {
        throw NoteCodecError.malformed("not used in these tests")
    }
}
