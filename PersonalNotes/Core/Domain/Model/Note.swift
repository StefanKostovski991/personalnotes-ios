import SwiftUI

/// Where a note's text came from. Mirrors Android's `NoteKind`.
enum NoteKind: String, CaseIterable, Codable, Sendable {
    case typed
    case spoken
    case mixed

    var label: String {
        switch self {
        case .typed: return "Typed"
        case .spoken: return "Spoken"
        case .mixed: return "Typed + spoken"
        }
    }

    var symbolName: String {
        switch self {
        case .typed: return "square.and.pencil"
        case .spoken: return "mic.fill"
        case .mixed: return "waveform"
        }
    }

    init(id: String?) {
        self = id.flatMap(NoteKind.init(rawValue:)) ?? .typed
    }
}

/// A place a note was written at. Coordinates are optional because the user may type a place by
/// hand or decline the location prompt.
struct NoteLocation: Equatable, Codable, Sendable {
    var label: String
    var latitude: Double?
    var longitude: Double?

    init(label: String = "", latitude: Double? = nil, longitude: Double? = nil) {
        self.label = label
        self.latitude = latitude
        self.longitude = longitude
    }

    var hasCoordinates: Bool { latitude != nil && longitude != nil }

    var isEmpty: Bool { label.trimmingCharacters(in: .whitespaces).isEmpty && !hasCoordinates }

    static let empty = NoteLocation()
}

/// A note as the rest of the app understands it, free of storage detail.
///
/// `fileRefs` holds app-private file names (never absolute paths) so a note stays portable.
struct Note: Identifiable, Equatable, Sendable {
    /// `nil` until the note has been persisted for the first time.
    var id: UUID?
    var title: String
    var description: String
    var createdAt: Date
    var updatedAt: Date
    var location: NoteLocation
    var color: NoteColor
    var kind: NoteKind
    var fileRefs: [String]

    init(
        id: UUID? = nil,
        title: String = "",
        description: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        location: NoteLocation = .empty,
        color: NoteColor = .default,
        kind: NoteKind = .typed,
        fileRefs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.location = location
        self.color = color
        self.kind = kind
        self.fileRefs = fileRefs
    }

    static let untitled = "Untitled note"

    var displayTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.untitled : title }

    var hasDescription: Bool { !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var isPersisted: Bool { id != nil }

    var voiceRef: String? { fileRefs.first }

    var hasVoice: Bool { voiceRef != nil }

    /// True when there is something worth saving.
    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !fileRefs.isEmpty
    }
}

/// What the editor holds before the note is persisted.
struct NoteDraft: Equatable, Sendable {
    var id: UUID?
    var title: String = ""
    var description: String = ""
    var createdAt: Date = .now
    var location: NoteLocation = .empty
    var color: NoteColor = .default
    var kind: NoteKind = .typed
    var fileRefs: [String] = []
}

/// Sort orders offered on the notes list.
enum NoteSort: String, CaseIterable, Identifiable, Sendable {
    case newest
    case oldest
    case title
    case color

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        case .title: return "Title A-Z"
        case .color: return "By colour"
        }
    }

    static let `default`: NoteSort = .newest
}

/// Filters applied on top of the stored notes.
struct NoteFilter: Equatable, Sendable {
    var query: String = ""
    var color: NoteColor?
    var sort: NoteSort = .default

    static let all = NoteFilter()
}

/// Where an incoming shared note came from.
enum NoteImportSource: Sendable {
    case file
    case link
}

/// Outcome of ingesting a note shared by another user of the app.
enum NoteImportResult: Sendable {
    case imported(Note)
    case alreadyExists(Note)
    case failed(String)
}
