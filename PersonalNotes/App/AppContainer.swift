import Foundation

/// The app's object graph.
///
/// A hand-written composition root instead of a DI framework: the graph is small, everything is
/// constructor-injected, and the domain stays free of framework types. Swapping in a container
/// later only means replacing this one type.
@MainActor
final class AppContainer: ObservableObject {
    let store: NoteFileStore
    let noteRepository: NoteRepository
    let shareRepository: NoteShareRepository
    let locationProvider: LocationProvider
    let voiceRecorder: VoiceRecorder
    let voicePlayer: VoicePlayer
    let dictation: DictationService

    let observeNotes: ObserveNotesUseCase
    let getNote: GetNoteUseCase
    let upsertNote: UpsertNoteUseCase
    let deleteNote: DeleteNoteUseCase
    let importNote: ImportNoteUseCase
    let exportNote: ExportNoteUseCase
    let buildNoteLink: BuildNoteLinkUseCase

    init(store: NoteFileStore = NoteFileStore()) {
        self.store = store
        self.noteRepository = FileNoteRepository(store: store)
        self.shareRepository = FileNoteShareRepository(store: store)
        self.locationProvider = CoreLocationProvider()
        self.voiceRecorder = VoiceRecorder(store: store)
        self.voicePlayer = VoicePlayer(store: store)
        self.dictation = DictationService()

        self.observeNotes = ObserveNotesUseCase(repository: noteRepository)
        self.getNote = GetNoteUseCase(repository: noteRepository)
        self.upsertNote = UpsertNoteUseCase(repository: noteRepository)
        self.deleteNote = DeleteNoteUseCase(repository: noteRepository)
        self.importNote = ImportNoteUseCase(repository: noteRepository)
        self.exportNote = ExportNoteUseCase(repository: shareRepository)
        self.buildNoteLink = BuildNoteLinkUseCase(repository: shareRepository)
    }
}
