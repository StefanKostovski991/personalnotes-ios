import SwiftUI

/// The animated splash: a three-stage entrance over the signature yellow gradient, finishing well
/// inside the time a launch already takes, so the user never waits on an animation.
struct SplashView: View {
    let onFinished: () -> Void

    @State private var markScale: CGFloat = 0.55
    @State private var markRotation: Double = -14
    @State private var markOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 28
    @State private var taglineOpacity: Double = 0
    @State private var breathing = false
    @State private var sweep: CGFloat = -0.4

    var body: some View {
        ZStack {
            Gradients.standard.signature
                .ignoresSafeArea(.all, edges: .all)

            // Decorative light sweep.
            LinearGradient(
                colors: [.clear, .white.opacity(0.45), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.35)
            .offset(x: sweep * 900)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .fill(Palette.caramel.opacity(0.34))
                        .frame(width: 132, height: 132)
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Palette.honeyDeep, Palette.caramel],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 104, height: 104)
                    NotesLogo(size: 92)
                }
                .scaleEffect(markScale * (breathing ? 1.06 : 1.0))
                .rotationEffect(.degrees(markRotation))
                .opacity(markOpacity)

                Text("Personal Notes")
                    .font(.system(size: 36, weight: .heavy, design: .default))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 28)
                    .offset(y: titleOffset)
                    .opacity(titleOpacity)

                Text("Write it. Say it. Keep it.")
                    .font(.headline)
                    .foregroundStyle(Palette.ink.opacity(0.72))
                    .padding(.top, 10)
                    .opacity(taglineOpacity)
            }
        }
        .task {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                breathing = true
            }
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                sweep = 1.4
            }

            withAnimation(.easeOut(duration: 0.52)) { markOpacity = 1 }
            withAnimation(.spring(response: 0.76, dampingFraction: 0.62)) {
                markScale = 1
                markRotation = 0
            }
            try? await Task.sleep(nanoseconds: 320_000_000)
            withAnimation(.easeOut(duration: 0.46)) { titleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.52)) { titleOffset = 0 }
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.easeOut(duration: 0.42)) { taglineOpacity = 1 }
            try? await Task.sleep(nanoseconds: 600_000_000)
            onFinished()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Personal Notes is starting")
    }
}
