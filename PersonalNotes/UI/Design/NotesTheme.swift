import SwiftUI

extension Color {
    /// Builds a colour from a 0xRRGGBB literal, matching the Android palette definitions.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// The app's palette: the same warm yellow identity as the Android app, value for value.
enum Palette {
    // Gradient stops, bright to deep - the signature look.
    static let sunlight = Color(hex: 0xFFF8DC)
    static let butter = Color(hex: 0xFFE9A3)
    static let gold = Color(hex: 0xFFC93C)
    static let amber = Color(hex: 0xFFA000)
    static let honeyDeep = Color(hex: 0xF57F17)
    static let caramel = Color(hex: 0xB35C00)

    // Ink.
    static let ink = Color(hex: 0x2E2506)
    static let inkSoft = Color(hex: 0x6B5B22)
    static let inkFaint = Color(hex: 0x9C8B4E)
    static let cream = Color(hex: 0xFFFDF5)
    static let paper = Color.white

    // State.
    static let success = Color(hex: 0x2E7D32)
    static let danger = Color(hex: 0xC62828)
    static let info = Color(hex: 0x00796B)
}

/// The gradient brushes used across the app, so screens never hard-code colours.
struct Gradients {
    let signature: LinearGradient
    let subtle: LinearGradient
    let card: LinearGradient
    let glow: RadialGradient

    static let standard = Gradients(
        signature: LinearGradient(
            colors: [Palette.butter, Palette.gold, Palette.amber],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        subtle: LinearGradient(
            colors: [Palette.sunlight, Palette.cream, Color(hex: 0xFFF4CE)],
            startPoint: .top,
            endPoint: .bottom
        ),
        card: LinearGradient(
            colors: [Palette.paper, Color(hex: 0xFFF7E0)],
            startPoint: .top,
            endPoint: .bottom
        ),
        glow: RadialGradient(
            colors: [Palette.amber.opacity(0.28), .clear],
            center: .center,
            startRadius: 4,
            endRadius: 260
        )
    )
}

extension View {
    /// The app-wide background gradient behind any screen.
    func notesBackground(_ gradients: Gradients = .standard) -> some View {
        background(gradients.subtle.ignoresSafeArea())
    }
}

/// Generous rounding is part of the "fancy" look: soft cards, pill buttons.
enum Radius {
    static let card: CGFloat = 26
    static let panel: CGFloat = 24
    static let control: CGFloat = 20
    static let pill: CGFloat = 999
}
