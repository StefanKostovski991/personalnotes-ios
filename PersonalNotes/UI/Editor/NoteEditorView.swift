import SwiftUI

/// Where a note is written: type it, dictate it, record it, tag the place and pick a colour.
struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: EditorModel
    @StateObject private var shareModel: ShareModel

    @State private var showShareSheet = false

    init(container: AppContainer, noteID: UUID?, startInSpeakingMode: Bool = false) {
        _model = StateObject(
            wrappedValue: EditorModel(
                container: container,
                noteID: noteID,
                startInSpeakingMode: startInSpeakingMode
            )
        )
        _shareModel = StateObject(wrappedValue: ShareModel(container: container))
    }

    var body: some View {
        ZStack {
            Gradients.standard.subtle.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 16) {
                        modeSelector
                        titleField

                        if model.mode == .typing {
                            typingPanel
                        } else {
                            speakingPanel
                        }

                        voicePanel
                        locationPanel
                        colorPanel

                        Button {
                            Task {
                                await model.save()
                                if model.didSave { dismiss() }
                            }
                        } label: {
                            Text(model.isNew ? "Save note" : "Save changes")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                        .fill(Palette.amber)
                                )
                        }
                        .disabled(!model.hasContent || model.isSaving)
                        .opacity(model.hasContent ? 1 : 0.5)
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .task(id: model.shareAfterSave) {
            guard model.shareAfterSave, let id = model.noteID else { return }
            showShareSheet = true
            await shareModel.prepare(noteID: id)
        }
        .sheet(isPresented: $showShareSheet) {
            NoteShareView(model: shareModel) {
                showShareSheet = false
                dismiss()
            }
            .presentationBackground { Gradients.standard.subtle }
        }
        .onChange(of: model.didSave) { _, saved in
            if saved { dismiss() }
        }
        .onChange(of: model.message) { _, message in
            guard message != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                model.message = nil
            }
        }
        .alert(
            "Personal Notes",
            isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            ),
            presenting: model.message
        ) { _ in
            Button("OK") { model.message = nil }
        } message: { message in
            Text(message)
        }
        .onDisappear {
            model.dictation.cancel()
            model.playback.stop()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await model.save()
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 42, height: 42)
            }
            .accessibilityLabel("Back and save")

            Text(model.isNew ? "New note" : "Edit note")
                .font(.title3.weight(.heavy))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await model.share() }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.ink.opacity(model.hasContent ? 1 : 0.4))
                    .frame(width: 42, height: 42)
            }
            .disabled(!model.hasContent)
            .accessibilityLabel("Share this note")

            Button {
                Task {
                    await model.save()
                    if model.didSave { dismiss() }
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.ink.opacity(model.hasContent ? 1 : 0.4))
                    .frame(width: 42, height: 42)
            }
            .disabled(!model.hasContent || model.isSaving)
            .accessibilityLabel("Save note")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Gradients.standard.signature)
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    // MARK: - Sections

    private var modeSelector: some View {
        HStack(spacing: 0) {
            ForEach(EditorMode.allCases, id: \.self) { mode in
                Button {
                    model.changeMode(mode)
                } label: {
                    Label(mode.label, systemImage: mode.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(model.mode == mode ? .white : Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(model.mode == mode ? Palette.amber : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Palette.butter.opacity(0.55)))
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.inkSoft)
            TextField("What is this about?", text: $model.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Palette.paper)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Palette.inkFaint.opacity(0.25), lineWidth: 1)
                )
        }
    }

    private var typingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.inkSoft)
            TextEditor(text: Binding(
                get: { model.description },
                set: { model.editDescription($0) }
            ))
            .font(.body)
            .foregroundStyle(Palette.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 180)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Palette.inkFaint.opacity(0.25), lineWidth: 1)
            )

            HStack {
                Button {
                    model.changeMode(.speaking)
                    model.toggleDictation()
                } label: {
                    Label("Dictate instead", systemImage: "waveform.and.mic")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.amber)
                }
                Spacer()
                if model.hasVoice {
                    StatusPill(text: "Has a recording", tone: Palette.success)
                }
            }
        }
    }

    private var speakingPanel: some View {
        VStack(spacing: 12) {
            Text("Speak your note")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("Your words appear below and can be edited afterwards.")
                .font(.footnote)
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)

            Button {
                model.toggleDictation()
            } label: {
                PulsingMic(
                    level: dictationLevel,
                    isActive: model.dictation.isListening
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.dictation.isListening ? "Stop dictation" : "Start dictation")

            dictationStatus

            TextEditor(text: Binding(
                get: { model.description },
                set: { model.editDescription($0) }
            ))
            .font(.body)
            .foregroundStyle(Palette.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 150)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Palette.paper)
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Gradients.standard.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.gold.opacity(0.5), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var dictationStatus: some View {
        switch model.dictation.state {
        case .listening:
            StatusPill(text: "Listening...", tone: Palette.danger)
        case .heard:
            StatusPill(text: "Tap to keep listening", tone: Palette.success)
        case .notice(let text):
            StatusPill(text: text, tone: Palette.info)
        case .failed(let reason):
            StatusPill(text: reason, tone: Palette.danger)
        case .idle:
            StatusPill(text: "Tap the mic to start", tone: Palette.info)
        }
    }

    private var dictationLevel: Double {
        if case .heard(let text) = model.dictation.state {
            return min(Double(text.count) / 120, 1)
        }
        return 0.35
    }

    private var voicePanel: some View {
        EditorPanel(title: "Voice note", systemImage: "waveform") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recordingSummary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    if case .recording(let elapsed, _) = model.recorder.state {
                        Text("Recording \(NotesDateFormatter.elapsed(milliseconds: elapsed))")
                            .font(.caption)
                            .foregroundStyle(Palette.danger)
                    }
                }
                Spacer()

                if model.isRecording {
                    Button {
                        model.cancelRecording()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(Palette.inkSoft)
                            .frame(width: 38, height: 38)
                    }
                    .accessibilityLabel("Discard recording")

                    Button {
                        model.toggleRecording()
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(Palette.danger)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(.white))
                    }
                    .accessibilityLabel("Stop recording")
                } else {
                    Button {
                        model.toggleRecording()
                    } label: {
                        Label(model.hasVoice ? "Re-record" : "Record", systemImage: "mic.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Palette.amber))
                    }
                }
            }

            if case .recording(_, let level) = model.recorder.state {
                ProgressView(value: level)
                    .tint(Palette.amber)
            }

            if model.hasVoice && !model.isRecording {
                HStack(spacing: 12) {
                    Button {
                        model.togglePlayback()
                    } label: {
                        Image(systemName: model.playback.state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.caramel)
                            .frame(width: 38, height: 38)
                    }
                    .accessibilityLabel(model.playback.state.isPlaying ? "Pause" : "Play")

                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: model.playback.state.progress)
                            .tint(Palette.caramel)
                        Text("\(NotesDateFormatter.duration(model.playback.state.position)) / \(NotesDateFormatter.duration(model.playback.state.duration))")
                            .font(.caption2)
                            .foregroundStyle(Palette.inkSoft)
                    }

                    Button {
                        model.removeRecording()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Palette.inkSoft)
                            .frame(width: 38, height: 38)
                    }
                    .accessibilityLabel("Remove recording")
                }

                if let error = model.playback.state.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Palette.danger)
                }
            }
        }
    }

    private var recordingSummary: String {
        if model.isRecording { return "Recording..." }
        return model.hasVoice ? "Saved recording attached" : "Record audio for this note"
    }

    private var locationPanel: some View {
        EditorPanel(title: "Where", systemImage: "mappin.and.ellipse") {
            Text(model.location.label.isEmpty ? "No place attached" : model.location.label)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)

            HStack(spacing: 10) {
                TextField("Or type a place", text: Binding(
                    get: { model.location.label },
                    set: { model.editLocationLabel($0) }
                ))
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Palette.paper)
                )

                Button {
                    Task { await model.captureLocation() }
                } label: {
                    Label(model.isLocating ? "Locating..." : "Use my location", systemImage: "location.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Palette.amber))
                }
                .disabled(model.isLocating)
            }

            if !model.location.label.isEmpty {
                Button {
                    model.clearLocation()
                } label: {
                    Label("Remove place", systemImage: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.inkSoft)
                }
            }

            MetaChip(
                systemImage: "checkmark",
                text: NotesDateFormatter.fullTimestamp(model.createdAt),
                tint: Palette.inkSoft
            )
        }
    }

    private var colorPanel: some View {
        EditorPanel(title: "Colour tag", systemImage: "paintpalette") {
            HStack(spacing: 12) {
                ForEach(NoteColor.allCases) { color in
                    ColorSwatch(color: color, selected: model.color == color) {
                        model.color = color
                    }
                }
                Spacer(minLength: 0)
            }
            Text(model.color.label)
                .font(.caption)
                .foregroundStyle(Palette.inkSoft)
        }
    }
}
