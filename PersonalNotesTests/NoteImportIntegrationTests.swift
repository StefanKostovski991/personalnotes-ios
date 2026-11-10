import XCTest
@testable import PersonalNotes

/// End-to-end import through the real file-backed repository: parse a payload produced by the
/// Android app, store it, and confirm it survives a reload and is not duplicated.
@MainActor
final class NoteImportIntegrationTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalNotesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeRepository() -> (NoteRepository, NoteFileStore) {
        let store = NoteFileStore(rootDirectory: directory)
        return (FileNoteRepository(store: store), store)
    }

    private func androidPayload(id: String = "android-1", title: String = "Amber spoken") -> Data {
        let payload = NotePayload(
            id: id,
            title: title,
            description: "dictated on Android",
            createdAt: 1_750_000_000_000,
            updatedAt: 1_750_000_500_000,
            colorId: "amber",
            kindId: "spoken",
            location: NoteLocationPayload(label: "Vienna", latitude: 48.2082, longitude: 16.3738)
        )
        return try! NotePayloadCodec.encodeToFileBytes(payload)
    }

    func testImportPersistsNoteWithAllFields() async throws {
        let (repository, _) = makeRepository()

        let result = await repository.importNote(data: androidPayload(), source: .file)
        guard case .imported(let note) = result else {
            return XCTFail("expected the note to be imported, got \(result)")
        }
        XCTAssertEqual(note.title, "Amber spoken")
        XCTAssertEqual(note.color, .amber)
        XCTAssertEqual(note.kind, .spoken)
        XCTAssertEqual(note.location.label, "Vienna")
        XCTAssertEqual(note.location.latitude ?? 0, 48.2082, accuracy: 0.0001)
    }

    func testImportIsIdempotentAcrossReloads() async throws {
        let (repository, store) = makeRepository()
        _ = await repository.importNote(data: androidPayload(), source: .file)

        // A fresh repository reads the same file, as after an app relaunch.
        let reloaded = FileNoteRepository(store: store)
        let second = await reloaded.importNote(data: androidPayload(), source: .link)

        guard case .alreadyExists = second else {
            return XCTFail("the same note must not be stored twice, got \(second)")
        }
    }

    func testImportedNoteIsVisibleInStream() async throws {
        let (repository, _) = makeRepository()
        _ = await repository.importNote(data: androidPayload(), source: .file)

        var iterator = repository.observeNotes().makeAsyncIterator()
        let first = await iterator.next() ?? []
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.title, "Amber spoken")
    }

    func testSavingNoteWritesAttachmentIntoPermanentStorage() async throws {
        let (repository, store) = makeRepository()
        // Mimic an unsaved recording living in the temporary directory.
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersonalNotes", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let tempFile = tempDirectory.appendingPathComponent("voice-test.m4a")
        try Data([1, 2, 3, 4]).write(to: tempFile)

        let note = Note(title: "With voice", description: "hello", fileRefs: [tempFile.lastPathComponent])
        let id = try await repository.save(note)

        let saved = await repository.note(id: id)
        XCTAssertEqual(saved?.fileRefs, ["voice-test.m4a"])
        XCTAssertTrue(store.exists("voice-test.m4a"), "the recording must be persisted with the note")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path), "the cache copy should be moved")
    }

    func testDeletingNoteRemovesItsAttachment() async throws {
        let (repository, store) = makeRepository()
        try FileManager.default.createDirectory(at: store.attachmentsDirectory, withIntermediateDirectories: true)
        let ref = try store.writeAttachment(name: "voice-del.m4a", data: Data([9]))
        let id = try await repository.save(Note(title: "To delete", fileRefs: [ref]))

        try await repository.delete(id: id)

        XCTAssertFalse(store.exists(ref))
        let remaining = await repository.note(id: id)
        XCTAssertNil(remaining)
    }

    func testMalformedFileIsRejected() async throws {
        let (repository, _) = makeRepository()
        let result = await repository.importNote(data: Data("not a note".utf8), source: .file)
        guard case .failed = result else {
            return XCTFail("malformed input must be reported, got \(result)")
        }
    }
}
