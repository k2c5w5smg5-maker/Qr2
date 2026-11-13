import AVFoundation
import Speech

/// Live speech-to-text for spoken label instructions. Uses on-device recognition when the
/// device supports it, so dictation works offline and audio never leaves the phone.
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false

    func toggle() async {
        if isListening { stop() } else { await start() }
    }

    func start() async {
        guard await Self.requestPermissions() else {
            errorMessage = "Allow Microphone and Speech Recognition for this app in Settings to dictate labels."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        stop()
        transcript = ""

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request

            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            engine.prepare()
            try engine.start()
            isListening = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = error != nil || (result?.isFinal ?? false)
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if finished { self.stop() }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        if isListening {
            isListening = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speech else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
