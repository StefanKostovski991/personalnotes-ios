import SwiftUI

/// The app mark: a ruled sheet of paper with a pencil resting across it.
struct NotesLogo: View {
    var size: CGFloat = 64

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("Personal Notes")
    }
}

/// Small pill label used for time, place and colour hints on a note.
struct MetaChip: View {
    let systemImage: String
    let text: String
    var tint: Color = Palette.inkSoft
    var background: Color = Palette.butter.opacity(0.55)

    var body: some View {
        if !text.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(text)
                    .font(.caption)
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(background))
        }
    }
}

/// The kind badge (typed / spoken / mixed) shown on a card.
struct KindBadge: View {
    let kind: NoteKind
    var tint: Color = Palette.inkSoft

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .accessibilityLabel(kind.label)
    }
}

/// A round colour swatch. The selected one grows and gains a check mark, which reads better than
/// colour alone.
struct ColorSwatch: View {
    let color: NoteColor
    let selected: Bool
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.surface)
                    .overlay(
                        Circle().strokeBorder(
                            selected ? Palette.ink : Palette.ink.opacity(0.18),
                            lineWidth: selected ? 2 : 1
                        )
                    )
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .frame(width: selected ? size + 6 : size, height: selected ? size + 6 : size)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A soft status pill, e.g. "Listening..." or an error message.
struct StatusPill: View {
    let text: String
    var tone: Color = Palette.info

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tone)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(tone.opacity(0.14)))
    }
}

/// Pulsing microphone halo used by the recorder. The pulse is decorative; the level is added on
/// top so the halo reacts to how loudly the user is speaking.
struct PulsingMic: View {
    var level: Double = 0.3
    var isActive: Bool = true

    @State private var pulse = false

    var body: some View {
        let scale = (pulse ? 1.18 : 0.9) + level * 0.25
        ZStack {
            Circle()
                .fill(Palette.amber.opacity(0.20))
                .frame(width: 96 * scale, height: 96 * scale)
            Circle()
                .fill(Palette.gold.opacity(0.35))
                .frame(width: 64 * scale, height: 64 * scale)
            Circle()
                .fill(Palette.caramel)
                .frame(width: 52, height: 52)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
        .frame(width: 140, height: 140)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { if isActive { pulse = true } }
        .onChange(of: isActive) { _, active in pulse = active }
    }
}

/// One note in the list: a soft gradient card with a thick colour rail on the leading edge.
struct NoteCard: View {
    let note: Note
    var now: Date = .now

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(note.color.accent)
                .frame(width: 8)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(note.displayTitle)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    KindBadge(kind: note.kind, tint: note.color.accent)
                }

                if note.hasDescription {
                    Text(note.description)
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 6) {
                    MetaChip(
                        systemImage: "checkmark",
                        text: NotesDateFormatter.noteTimestamp(note.updatedAt, now: now),
                        tint: Palette.inkSoft
                    )
                    if !note.location.label.isEmpty {
                        MetaChip(
                            systemImage: "mappin.and.ellipse",
                            text: note.location.label,
                            tint: Palette.inkSoft
                        )
                    }
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Gradients.standard.card)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(note.color.accent.opacity(0.35), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// A labelled section container used by the editor.
struct EditorPanel<Content: View>: View {
    let title: String?
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .foregroundStyle(Palette.inkSoft)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .fill(Palette.butter.opacity(0.45))
        )
    }
}
