import Foundation

/// Which note the editor should open, and how.
///
/// Identifiable so it can drive a `.sheet(item:)`: every presentation gets a fresh identity, which
/// keeps drafts from being reused between openings.
struct EditorContext: Identifiable {
    let id: UUID
    let noteID: UUID?
    let startInSpeakingMode: Bool

    static func new(startInSpeakingMode: Bool = false) -> EditorContext {
        EditorContext(id: UUID(), noteID: nil, startInSpeakingMode: startInSpeakingMode)
    }

    static func existing(_ note: Note) -> EditorContext {
        EditorContext(id: UUID(), noteID: note.id, startInSpeakingMode: false)
    }
}
