import AVFoundation
import Foundation

/// Lifecycle of a voice recording, observed by the editor.
enum RecordingState: Equatable {
    case idle
    case recording(elapsedMs: Int, level: Double)
    case finished(fileURL: URL, duration: TimeInterval)
    case failed(String)
}

/// Records a spoken note with `AVAudioRecorder`.
///
/// The file is created in the temporary directory and only moved into permanent storage when its
/// note is saved, so an abandoned draft leaves nothing behind.
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published private(set) var state: RecordingState = .idle

    private let store: NoteFileStore
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?
    private var ticker: Task<Void, Never>?
    private var outputURL: URL?

    init(store: NoteFileStore) {
        self.store = store
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var elapsedMilliseconds: Int {
        guard let startedAt else { return 0 }
        return Int(Date().timeIntervalSince(startedAt) * 1000)
    }

    @discardableResult
    func start() async -> Bool {
        guard !isRecording else { return true }
        guard await requestMicrophonePermission() else {
            state = .failed("Microphone access is needed to record a note")
            return false
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)

            let url = try store.newRecordingURL()
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.record()

            self.recorder = recorder
            self.outputURL = url
            self.startedAt = Date()
            self.state = .recording(elapsedMs: 0, level: 0)
            startTicker()
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    func stop() {
        guard let recorder else { return }
        let duration = TimeInterval(elapsedMilliseconds) / 1000
        let url = outputURL

        recorder.stop()
        self.recorder = nil
        self.outputURL = nil
        startedAt = nil
        ticker?.cancel()
        ticker = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            state = .failed("Nothing was recorded")
            return
        }
        state = .finished(fileURL: url, duration: max(duration, 0.5))
    }

    /// Drops the current recording without keeping the file.
    func discard() {
        ticker?.cancel()
        ticker = nil
        recorder?.stop()
        recorder = nil
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        outputURL = nil
        startedAt = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Called once the recording has been attached to a saved note.
    func consume() {
        state = .idle
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let level = Self.normalizedLevel(recorder.averagePower(forChannel: 0))
                self.state = .recording(elapsedMs: self.elapsedMilliseconds, level: level)
            }
        }
    }

    /// dBFS (-160...0) to a 0...1 level for the waveform.
    private static func normalizedLevel(_ power: Float) -> Double {
        let floor: Float = -50
        let clamped = max(power, floor)
        return Double((clamped - floor) / -floor)
    }

    private func requestMicrophonePermission() async -> Bool {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        return granted
    }
}
