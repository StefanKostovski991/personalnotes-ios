import AVFoundation
import Foundation
import Speech

/// Dictation state exposed to the editor.
enum DictationState: Equatable {
    case idle
    case listening
    /// Live/partial transcription.
    case heard(String)
    case notice(String)
    case failed(String)
}

/// Wraps `SFSpeechRecognizer` plus `AVAudioEngine`.
///
/// The recognizer delivers partial results while the user speaks and a final result when they
/// stop. The editor treats every update as "replace what dictation produced last", so the note
/// grows instead of duplicating text on each partial result.
@MainActor
final class DictationService: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var isAvailable: Bool

    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init(locale: Locale = Locale.current) {
        let recognizer = SFSpeechRecognizer(locale: locale)
        self.recognizer = recognizer
        self.isAvailable = recognizer?.isAvailable ?? false
    }

    var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    func start() async {
        guard let recognizer else {
            state = .failed("Speech recognition is not available on this device")
            return
        }
        guard await requestAuthorization() else {
            state = .failed("Speech recognition permission is needed to dictate a note")
            return
        }
        guard recognizer.isAvailable else {
            state = .failed("Speech recognition is temporarily unavailable")
            return
        }

        cancel()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                // Privacy: keep the audio on the device when the model is installed.
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    self?.handle(result: result, error: error)
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
            cleanupAudio()
        }
    }

    /// Stops capturing but lets the recognizer deliver its final result.
    func stop() {
        guard audioEngine.isRunning else { return }
        audioEngine.stop()
        request?.endAudio()
        state = .notice("Finishing...")
    }

    func cancel() {
        task?.cancel()
        task = nil
        request = nil
        cleanupAudio()
        state = .idle
    }

    func consume() {
        state = .idle
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            if result.isFinal {
                state = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .notice("Nothing was recognised - try again")
                    : .heard(text)
                cleanupAudio()
            } else if !text.isEmpty {
                state = .heard(text)
            }
        }
        if let error {
            // Code 1110 is kAFAssistantErrorDomain "no speech detected"; the raw description is
            // unhelpful for the user, so it gets a plain message.
            let message = (error as NSError).code == 1110
                ? "Nothing was recognised - try again"
                : error.localizedDescription
            if !message.isEmpty { state = .failed(message) }
            cleanupAudio()
        }
    }

    private func cleanupAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }
}
