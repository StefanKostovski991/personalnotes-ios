import SwiftUI
import UIKit

/// A UIActivityViewController wrapper, so files and links go through the system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Prepares one note for sending to another user of the app.
///
/// Two independent routes are offered because the receiver may not have a messenger that keeps
/// files intact: the link already contains the note, and the `.pnote` file is attached for
/// everything else.
@MainActor
final class ShareModel: ObservableObject {
    @Published private(set) var exported: ExportedNote?
    @Published private(set) var shareLink = ""
    @Published private(set) var isPreparing = true
    @Published var error: String?
    @Published var activityItems: [Any]?

    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    func prepare(noteID: UUID) async {
        guard let note = await container.getNote(id: noteID) else {
            error = "This note could not be found"
            isPreparing = false
            return
        }
        shareLink = container.buildNoteLink(note: note)
        do {
            exported = try await container.exportNote(note: note)
        } catch {
            self.error = error.localizedDescription
        }
        isPreparing = false
    }

    /// The `.pnote` file plus a short message, so the receiver knows what the attachment is.
    func shareFile() {
        guard let exported else { return }
        activityItems = [exported.fileURL]
    }

    func shareLinkOnly() {
        activityItems = ["\(shareLink)\n\nSent from Personal Notes"]
    }

    func copyLink() {
        UIPasteboard.general.string = shareLink
    }
}

/// The "send this note" sheet.
struct NoteShareView: View {
    @ObservedObject var model: ShareModel
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Gradients.standard.subtle.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        if model.isPreparing {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Preparing your note...")
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.inkSoft)
                            }
                            .padding(.vertical, 24)
                        } else if let error = model.error {
                            VStack(spacing: 10) {
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.danger)
                                    .multilineTextAlignment(.center)
                                Text("The note may be too large to share as a file.")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.inkSoft)
                            }
                            .padding()
                        } else {
                            action(
                                systemImage: "square.and.arrow.up",
                                title: "Send the note file",
                                subtitle: model.exported.map { "\($0.fileName)" } ?? "",
                                primary: true
                            ) { model.shareFile() }

                            action(
                                systemImage: "doc.on.doc",
                                title: "Copy the link",
                                subtitle: "The whole note travels inside the link",
                                primary: false
                            ) { model.copyLink() }

                            action(
                                systemImage: "link",
                                title: "Send the link",
                                subtitle: "Opens straight in their copy of the app",
                                primary: false
                            ) { model.shareLinkOnly() }

                            if !model.shareLink.isEmpty {
                                Text(model.shareLink)
                                    .font(.caption2)
                                    .foregroundStyle(Palette.inkSoft)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Palette.butter.opacity(0.6))
                                    )
                            }

                            Text("Whoever receives it taps the link or opens the file and it is added to their notes. Voice recordings travel inside the file too.")
                                .font(.footnote)
                                .foregroundStyle(Palette.inkSoft)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Share note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
            .sheet(item: Binding(
                get: { model.activityItems.map(ActivityItems.init) },
                set: { if $0 == nil { model.activityItems = nil } }
            )) { items in
                ShareSheet(items: items.items)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Identifiable wrapper so `.sheet(item:)` can present the activity controller.
    private struct ActivityItems: Identifiable {
        let id = UUID()
        let items: [Any]
        init(_ items: [Any]) { self.items = items }
    }

    private func action(
        systemImage: String,
        title: String,
        subtitle: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(primary ? .white.opacity(0.85) : Palette.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(primary ? .white : Palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(primary ? Palette.amber : Palette.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(primary ? .clear : Palette.inkFaint.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
