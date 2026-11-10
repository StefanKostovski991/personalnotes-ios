import SwiftUI

@main
struct PersonalNotesApp: App {
    @StateObject private var container: AppContainer
    @StateObject private var model: AppModel

    /// Note opened from a deep link, waiting for the list to be ready.
    @State private var pendingNoteID: UUID?

    init() {
        let container = AppContainer()
        _container = StateObject(wrappedValue: container)
        _model = StateObject(wrappedValue: AppModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, container: container, pendingNoteID: $pendingNoteID)
                .tint(Palette.amber)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    Task { pendingNoteID = await model.handleIncoming(url: url) }
                }
                .onAppear { model.start() }
        }
    }
}

/// Splash first, then the notebook.
struct RootView: View {
    @ObservedObject var model: AppModel
    let container: AppContainer
    @Binding var pendingNoteID: UUID?
    @State private var showSplash = true
    @State private var didHandleLaunchURL = false

    var body: some View {
        ZStack {
            NotesListView(
                model: model,
                container: container,
                pendingNoteID: $pendingNoteID
            )
            .opacity(showSplash ? 0 : 1)

            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.45)) { showSplash = false }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
                .zIndex(1)
            }
        }
        .task {
            await deliverLaunchURLIfNeeded()
        }
    }

    /// Debug/automation hook: `-incomingURL <url>` delivers a deep link on launch.
    ///
    /// Useful from the command line and in UI tests, where tapping the system "Open in" confirmation
    /// is not scriptable:
    ///     xcrun simctl launch <device> com.kostovskiapps.personalnotes \
    ///         -incomingURL "personalnotes://note/d/<token>"
    /// Only read once, and only when the argument is present, so normal launches are unaffected.
    private func deliverLaunchURLIfNeeded() async {
        guard !didHandleLaunchURL else { return }
        didHandleLaunchURL = true
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-incomingURL"),
              arguments.indices.contains(flagIndex + 1),
              let url = URL(string: arguments[flagIndex + 1]) else { return }
        pendingNoteID = await model.handleIncoming(url: url)
    }
}
