import UniformTypeIdentifiers

extension UTType {
    /// The `.pnote` document the app exports and opens. Declared in Info.plist as an exported
    /// type so Mail, Messages and Files hand it to Personal Notes.
    static let noteDocument = UTType(
        exportedAs: "com.kostovskiapps.personalnotes.note",
        conformingTo: .json
    )
}
