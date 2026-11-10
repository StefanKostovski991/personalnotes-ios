import Foundation
import SwiftUI

/// App-level state: the note list, the active filter, and incoming-note handling.
///
/// One observable model keeps every screen consistent; the domain use cases are called directly
/// from here, so there is no duplicated business logic between screens.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var filter = NoteFilter()
    @Published private(set) var isLoading = true
    @Published var banner: String?

    private let container: AppContainer
    private var observation: Task<Void, Never>?

    init(container: AppContainer) {
        self.container = container
    }

    /// Notes after the current search/colour filter and sort.
    var visibleNotes: [Note] {
        ObserveNotesUseCase.apply(notes, filter: filter)
    }

    var hasActiveFilter: Bool {
        !filter.query.trimmingCharacters(in: .whitespaces).isEmpty ||
            filter.color != nil ||
            filter.sort != .default
    }

    func start() {
        guard observation == nil else { return }
        let stream = ObserveNotesUseCase(repository: container.noteRepository).stream(filter: .all)
        observation = Task { [weak self] in
            for await updated in stream {
                guard let self else { return }
                self.notes = updated
                self.isLoading = false
            }
        }
    }

    func delete(_ note: Note) async {
        guard let id = note.id else { return }
        do {
            try await container.deleteNote(id: id)
        } catch {
            banner = "The note could not be deleted: \(error.localizedDescription)"
        }
    }

    func clearFilters() {
        filter = .all
    }

    // MARK: - Incoming notes

    /// Handles every incoming link/document. Returns a note id when the UI should open it.
    func handleIncoming(url: URL) async -> UUID? {
        // Links written by this app carry the note in the payload, so they always import.
        if let incoming = DeepLinkParser.parse(url) {
            switch incoming {
            case .localNote(let id):
                if notes.contains(where: { $0.id == id }) { return id }
                banner = "That note is not on this device"
                return nil

            case .embeddedNote(let token):
                return await importEmbedded(token)

            case .noteDocument(let url):
                return await importDocument(at: url)
            }
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "d" })?.value {
            return await importEmbedded(token)
        }

        banner = "This note could not be opened"
        return nil
    }

    private func importEmbedded(_ token: String) async -> UUID? {
        guard let data = try? NotePayloadCodec.encodeToFileBytes(try NotePayloadCodec.decodeLinkToken(token)) else {
            banner = "This note link could not be opened"
            return nil
        }
        return await importNote(data: data, source: .link)
    }

    private func importDocument(at url: URL) async -> UUID? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            banner = "That file could not be read"
            return nil
        }
        return await importNote(data: data, source: .file)
    }

    /// Shared import path for both files and links; idempotent through the content fingerprint.
    private func importNote(data: Data, source: NoteImportSource) async -> UUID? {
        switch await container.importNote(data: data, source: source) {
        case .imported(let note):
            banner = "Note added to your notebook"
            return note.id
        case .alreadyExists(let note):
            banner = "That note is already in your notebook"
            return note.id
        case .failed(let reason):
            banner = reason
            return nil
        }
    }
}
