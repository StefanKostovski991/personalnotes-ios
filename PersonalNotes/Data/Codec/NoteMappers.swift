import Foundation

/// Mapping between the domain model and the wire payload / on-disk entity.
///
/// Kept in one place so the JSON file format and the shared `.pnote` format cannot drift apart.
extension NotePayload {
    /// Domain payload for sending. `remoteId` is a stable string identity: a persisted note keeps
    /// its UUID, a new one gets a temporary marker.
    static func from(_ note: Note, attachments: [NoteAttachmentPayload] = [], id: String? = nil) -> NotePayload {
        let location = note.location.isEmpty ? nil : NoteLocationPayload(
            label: note.location.label,
            latitude: note.location.latitude,
            longitude: note.location.longitude
        )
        return NotePayload(
            id: id ?? note.id?.uuidString ?? "new-\(Int(Date().timeIntervalSince1970 * 1000))",
            title: note.title,
            description: note.description,
            createdAt: Int64(note.createdAt.timeIntervalSince1970 * 1000),
            updatedAt: Int64(note.updatedAt.timeIntervalSince1970 * 1000),
            colorId: note.color.rawValue,
            kindId: note.kind.rawValue,
            location: location,
            attachments: attachments
        )
    }

    /// Domain model with attachments already stored (turned into file refs).
    func toNote(id noteID: UUID? = nil, fileRefs: [String] = []) -> Note {
        Note(
            id: noteID,
            title: title,
            description: description,
            createdAt: Date(timeIntervalSince1970: Double(createdAt) / 1000),
            updatedAt: Date(timeIntervalSince1970: Double(updatedAt) / 1000),
            location: NoteLocation(
                label: location?.label ?? "",
                latitude: location?.latitude,
                longitude: location?.longitude
            ),
            color: NoteColor(id: colorId),
            kind: NoteKind(id: kindId),
            fileRefs: fileRefs
        )
    }
}
