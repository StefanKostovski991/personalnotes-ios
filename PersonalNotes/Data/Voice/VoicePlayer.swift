import AVFoundation
import Foundation

/// Playback state of the currently opened note's recording.
struct VoicePlayback: Equatable {
    var fileRef: String?
    var isPlaying: Bool = false
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var error: String?

    var hasTrack: Bool { fileRef != nil }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}

/// Plays the recording attached to the currently open note.
///
/// A single instance is shared through the composition root so moving between notes never leaves
/// a stray player running.
@MainActor
final class VoicePlayer: ObservableObject {
    @Published private(set) var state = VoicePlayback()

    private let store: NoteFileStore
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    init(store: NoteFileStore) {
        self.store = store
    }

    /// Declares which recording the screen is showing; stops playback when it changes.
    func attach(fileRef: String?) {
        guard state.fileRef != fileRef else { return }
        stop()
        state = VoicePlayback(fileRef: fileRef)
    }

    func toggle() {
        state.isPlaying ? pause() : play()
    }

    func play() {
        guard let fileRef = state.fileRef else { return }
        if let player {
            player.play()
            state.isPlaying = true
            startTicker()
            return
        }
        guard let url = store.attachmentURL(fileRef),
              FileManager.default.fileExists(atPath: url.path) else {
            state.error = "The recording is missing"
            state.isPlaying = false
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            self.player = player
            state.duration = player.duration
            state.isPlaying = true
            state.error = nil
            startTicker()
        } catch {
            state.error = error.localizedDescription
            state.isPlaying = false
        }
    }

    func pause() {
        player?.pause()
        ticker?.cancel()
        ticker = nil
        state.isPlaying = false
    }

    func seek(to fraction: Double) {
        guard let player, player.duration > 0 else { return }
        let target = player.duration * min(max(fraction, 0), 1)
        player.currentTime = target
        state.position = target
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        state.isPlaying = false
        state.position = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self, let player = self.player else { return }
                self.state.position = player.currentTime
                self.state.duration = player.duration
                if !player.isPlaying {
                    self.state.isPlaying = false
                    self.state.position = 0
                    self.stop()
                    return
                }
            }
        }
    }
}
