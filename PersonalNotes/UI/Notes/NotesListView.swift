import SwiftUI

/// The home screen: every stored note, newest first, with search, colour filter and sort.
struct NotesListView: View {
    @ObservedObject var model: AppModel
    let container: AppContainer
    @Binding var pendingNoteID: UUID?

    @State private var editorContext: EditorContext?
    @State private var notePendingDeletion: Note?
    @State private var showSortMenu = false
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            ZStack {
                Gradients.standard.subtle.ignoresSafeArea()

                VStack(spacing: 14) {
                    header
                    searchField
                    colorFilter

                    if model.isLoading {
                        loadingState
                    } else if model.visibleNotes.isEmpty && model.notes.isEmpty {
                        emptyState
                    } else if model.visibleNotes.isEmpty {
                        noMatchesState
                    } else {
                        noteList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack {
                    Spacer()
                    bottomActions
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $editorContext) { context in
                NoteEditorView(
                    container: container,
                    noteID: context.noteID,
                    startInSpeakingMode: context.startInSpeakingMode
                )
                .presentationBackground { Gradients.standard.subtle }
            }
            .task(id: pendingNoteID) {
                guard let id = pendingNoteID else { return }
                if let note = model.notes.first(where: { $0.id == id }) {
                    editorContext = .existing(note)
                }
                pendingNoteID = nil
            }
            .alert(
                "Delete this note?",
                isPresented: Binding(
                    get: { notePendingDeletion != nil },
                    set: { if !$0 { notePendingDeletion = nil } }
                ),
                presenting: notePendingDeletion
            ) { note in
                Button("Delete", role: .destructive) {
                    Task { await model.delete(note) }
                    notePendingDeletion = nil
                }
                Button("Keep", role: .cancel) { notePendingDeletion = nil }
            } message: { note in
                Text("\"\(note.displayTitle)\" and its recording will be removed from this device.")
            }
            .overlay(alignment: .top) {
                if let banner = model.banner {
                    TransientBanner(text: banner) { model.banner = nil }
                        .padding(.top, 8)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.noteDocument, .json, .data],
                allowsMultipleSelection: true
            ) { result in
                guard case .success(let urls) = result else { return }
                Task {
                    for url in urls {
                        pendingNoteID = await model.handleIncoming(url: url)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            NotesLogo(size: 58)

            VStack(alignment: .leading, spacing: 2) {
                Text("My notes")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            headerButton("folder", "Open a shared note file") { showImporter = true }

            Menu {
                ForEach(NoteSort.allCases) { sort in
                    Button {
                        model.filter.sort = sort
                    } label: {
                        if model.filter.sort == sort {
                            Label(sort.label, systemImage: "checkmark")
                        } else {
                            Text(sort.label)
                        }
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(.white.opacity(0.45)))
            }
            .accessibilityLabel("Change sorting")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Gradients.standard.signature)
        )
    }

    private var subtitle: String {
        let total = model.notes.count
        let visible = model.visibleNotes.count
        switch total {
        case 0: return "Nothing saved yet"
        case 1: return "1 note on this device"
        default: return visible == total
            ? "\(total) notes on this device"
            : "\(visible) of \(total) notes"
        }
    }

    private func headerButton(_ systemImage: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 46, height: 46)
                .background(Circle().fill(.white.opacity(0.45)))
        }
        .accessibilityLabel(label)
    }

    // MARK: - Filters

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.inkSoft)
            TextField("Search title, text or place", text: $model.filter.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !model.filter.query.isEmpty {
                Button {
                    model.filter.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.inkFaint)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Capsule().fill(Palette.paper))
        .overlay(Capsule().strokeBorder(Palette.inkFaint.opacity(0.25), lineWidth: 1))
    }

    private var colorFilter: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.inkSoft)

            Button {
                model.filter.color = nil
            } label: {
                Text("All")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(model.filter.color == nil ? .white : Palette.inkSoft)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(model.filter.color == nil ? Palette.amber : Palette.butter)
                    )
            }

            ForEach(NoteColor.allCases) { color in
                ColorSwatch(
                    color: color,
                    selected: model.filter.color == color,
                    size: 28
                ) {
                    model.filter.color = model.filter.color == color ? nil : color
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - List

    private var noteList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(model.visibleNotes) { note in
                    Button {
                        editorContext = .existing(note)
                    } label: {
                        NoteCard(note: note)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            notePendingDeletion = note
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 150)
        }
        .scrollIndicators(.hidden)
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            Spacer()
            Button {
                editorContext = .new(startInSpeakingMode: true)
            } label: {
                Label("Speak", systemImage: "mic.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Palette.butter))
            }

            Button {
                editorContext = .new()
            } label: {
                Label("New note", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Palette.amber))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Empty states

    private var loadingState: some View {
        VStack {
            Spacer()
            Text("Opening your notebook...")
                .font(.body)
                .foregroundStyle(Palette.inkSoft)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Gradients.standard.signature)
                    .frame(width: 112, height: 112)
                NotesLogo(size: 96)
            }
            Text("Your notebook is empty")
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.ink)
            Text("Type a note or hold the mic and speak - notes stay on this device until you share them.")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            HStack(spacing: 12) {
                Button {
                    editorContext = .new()
                } label: {
                    Text("Write a note")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Palette.amber))
                }
                Button {
                    editorContext = .new(startInSpeakingMode: true)
                } label: {
                    Label("Speak a note", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Palette.butter))
                }
            }
            Spacer()
        }
        .padding(.bottom, 80)
    }

    private var noMatchesState: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("No notes match that filter")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Button("Clear filters") { model.clearFilters() }
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
    }
}

/// A short-lived message at the top of the screen.
struct TransientBanner: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
            Text(text)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .accessibilityLabel("Dismiss")
        }
        .foregroundStyle(Palette.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Palette.butter))
        .overlay(Capsule().strokeBorder(Palette.gold, lineWidth: 1))
        .padding(.horizontal, 24)
        .transition(.move(edge: .top).combined(with: .opacity))
        .task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            withAnimation { onDismiss() }
        }
    }
}
