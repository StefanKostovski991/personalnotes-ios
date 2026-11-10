import Combine
import Foundation

/// How the user is entering this note; drives which input tools are shown.
enum EditorMode: String, CaseIterable {
    case typing
    case speaking

    var label: String { self == .typing ? "Type" : "Speak" }
    var symbolName: String { self == .typing ? "keyboard" : "mic.fill" }
}

/// State of one note being written.
///
/// Inputs are deliberately additive: dictation appends to whatever is already written, so the
/// user can type a line and then speak the rest into the same note.
@MainActor
final class EditorModel: ObservableObject {
    @Published var title = ""
    @Published var description = ""
    @Published var color: NoteColor = .default
    @Published var location: NoteLocation = .empty
    @Published var mode: EditorMode = .typing
    @Published private(set) var createdAt = Date()
    @Published private(set) var noteID: UUID?
    @Published private(set) var fileRefs: [String] = []
    @Published var isLocating = false
    @Published var message: String?
    @Published private(set) var isSaving = false

    /// Set after a save when the user pressed Share, so the sheet can present.
    @Published var shareAfterSave = false
    @Published var didSave = false

    private let container: AppContainer
    private let noteIDToLoad: UUID?
    private var lastDictated = ""
    private var cancellables: Set<AnyCancellable> = []

    init(container: AppContainer, noteID: UUID?, startInSpeakingMode: Bool) {
        self.container = container
        self.noteIDToLoad = noteID
        self.mode = startInSpeakingMode ? .speaking : .typing

        container.dictation.$state
            .sink { [weak self] state in self?.applyDictation(state) }
            .store(in: &cancellables)

        container.voiceRecorder.$state
            .sink { [weak self] state in
                guard let self else { return }
                if case .finished(let url, _) = state {
                    let name = url.lastPathComponent
                    if !self.fileRefs.contains(name) {
                        self.fileRefs.append(name)
                    }
                    container.voicePlayer.attach(fileRef: name)
                }
                if case .failed(let reason) = state {
                    self.message = reason
                }
            }
            .store(in: &cancellables)

        if let noteID {
            Task { await load(noteID) }
        }
    }

    var isNew: Bool { noteID == nil }

    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !fileRefs.isEmpty
    }

    var recorder: VoiceRecorder { container.voiceRecorder }
    var dictation: DictationService { container.dictation }
    var playback: VoicePlayer { container.voicePlayer }

    var isRecording: Bool { container.voiceRecorder.isRecording }

    var hasVoice: Bool { !fileRefs.isEmpty }

    var recordedDuration: TimeInterval {
        if case .finished(_, let duration) = container.voiceRecorder.state { return duration }
        return playback.state.duration
    }

    // MARK: - Loading

    private func load(_ id: UUID) async {
        guard let note = await container.getNote(id: id) else {
            message = "This note could not be found"
            return
        }
        noteID = note.id
        title = note.title
        description = note.description
        color = note.color
        location = note.location
        createdAt = note.createdAt
        fileRefs = note.fileRefs
        mode = note.hasVoice ? .speaking : .typing
        container.voicePlayer.attach(fileRef: note.voiceRef)
    }

    // MARK: - Editing

    func changeMode(_ newMode: EditorMode) {
        mode = newMode
        if newMode == .typing, container.dictation.isListening {
            container.dictation.stop()
        }
    }

    func editDescription(_ value: String) {
        // Manual edits invalidate the dictation diffing baseline.
        lastDictated = ""
        description = value
    }

    func editLocationLabel(_ value: String) {
        location.label = value
    }

    /// Replaces the text dictation produced last, so partial results grow the note instead of
    /// duplicating it on every recognizer update.
    private func applyDictation(_ state: DictationState) {
        switch state {
        case .heard(let text):
            let previous = lastDictated
            var base = description
            if !previous.isEmpty, base.hasSuffix(previous) {
                base.removeLast(previous.count)
            }
            let separator = base.isEmpty || base.hasSuffix(" ") || base.hasSuffix("\n") ? "" : " "
            lastDictated = text
            description = base + separator + text
        case .failed(let reason):
            message = reason
        case .idle, .listening, .notice:
            break
        }
    }

    // MARK: - Dictation

    func toggleDictation() {
        if container.dictation.isListening {
            container.dictation.stop()
        } else {
            lastDictated = ""
            Task { await container.dictation.start() }
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        if container.voiceRecorder.isRecording {
            container.voiceRecorder.stop()
        } else {
            mode = .speaking
            Task { await container.voiceRecorder.start() }
        }
    }

    func cancelRecording() {
        container.voiceRecorder.discard()
    }

    func removeRecording() {
        container.voicePlayer.stop()
        fileRefs = []
    }

    func togglePlayback() {
        guard let ref = fileRefs.first else { return }
        container.voicePlayer.attach(fileRef: ref)
        container.voicePlayer.toggle()
    }

    // MARK: - Location

    func captureLocation() async {
        isLocating = true
        defer { isLocating = false }
        do {
            location = try await container.locationProvider.currentLocation()
        } catch {
            message = error.localizedDescription
        }
    }

    func clearLocation() {
        location = .empty
    }

    // MARK: - Saving

    /// `share` = true saves and asks for the share sheet; otherwise the editor simply closes.
    func save(share: Bool = false) async {
        guard !isSaving else { return }
        if container.voiceRecorder.isRecording {
            container.voiceRecorder.stop()
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard hasContent else {
            message = "Add a title, some text or a recording first"
            return
        }

        isSaving = true
        defer { isSaving = false }

        let draft = NoteDraft(
            id: noteID,
            title: title,
            description: description,
            createdAt: createdAt,
            location: location,
            color: color,
            kind: kindForDraft(),
            fileRefs: fileRefs
        )
        do {
            switch try await container.upsertNote(draft) {
            case .saved(let id):
                noteID = id
                message = nil
                container.dictation.consume()
                if share {
                    shareAfterSave = true
                } else {
                    didSave = true
                }
            case .nothingToSave:
                message = "Nothing to save yet"
            }
        } catch {
            message = "The note could not be saved: \(error.localizedDescription)"
        }
    }

    func share() async {
        await save(share: true)
    }

    private func kindForDraft() -> NoteKind {
        if hasVoice && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .mixed
        }
        if hasVoice { return .spoken }
        return description.isEmpty ? .typed : .typed
    }
}
