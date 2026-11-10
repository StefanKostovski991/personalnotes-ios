import SwiftUI

/// The palette a note can be tagged with.
///
/// Values are identical to the Android app (`NoteColor` in Kotlin) so a note keeps its colour
/// when it travels between the two platforms. `id` is the stored/wire value, never the ordinal.
enum NoteColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case sunbeam
    case amber
    case honey
    case lemon
    case cream

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sunbeam: return "Sunbeam"
        case .amber: return "Amber"
        case .honey: return "Honey"
        case .lemon: return "Lemon"
        case .cream: return "Cream"
        }
    }

    /// Strong colour used for the rail, icons and selected states.
    var accent: Color {
        switch self {
        case .sunbeam: return Color(hex: 0xF9A825)
        case .amber: return Color(hex: 0xEF6C00)
        case .honey: return Color(hex: 0xC58A00)
        case .lemon: return Color(hex: 0x9E9D24)
        case .cream: return Color(hex: 0x8D6E63)
        }
    }

    /// Soft background the note sits on.
    var surface: Color {
        switch self {
        case .sunbeam: return Color(hex: 0xFFF3C4)
        case .amber: return Color(hex: 0xFFE7C2)
        case .honey: return Color(hex: 0xFDF0CE)
        case .lemon: return Color(hex: 0xF7F6C8)
        case .cream: return Color(hex: 0xF6ECDD)
        }
    }

    static let `default`: NoteColor = .sunbeam

    init(id: String?) {
        self = id.flatMap(NoteColor.init(rawValue:)) ?? .default
    }
}
