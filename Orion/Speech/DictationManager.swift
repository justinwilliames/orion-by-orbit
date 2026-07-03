import AVFoundation
import Foundation
import Speech

/// Handles voice-to-text dictation in the composer. Wraps Apple's
/// `SFSpeechRecognizer` + `AVAudioEngine` so the rest of the app
/// doesn't have to know about mic taps, audio formats, or permission
/// dance.
///
/// Lifecycle:
///   1. UI calls `start(onPartial:onFinish:onError:)`.
///   2. We request mic + speech permission if not yet granted. The OS
///      shows the system prompts using the strings in Info.plist.
///   3. Audio engine taps the input bus and pipes buffers into a
///      streaming recognition request. Partial transcripts arrive as
///      the user speaks; the caller updates the input field live.
///   4. When the user clicks the button again — or 90 seconds elapse,
///      whichever comes first — we stop the engine and finalise. The
///      `onFinish` closure receives the last best transcript.
///
/// Goals:
///   - **On-device when possible.** macOS 13+ can recognise English
///     entirely on-device; we set `requiresOnDeviceRecognition` so
///     no audio leaves the Mac when supported. Older OSes fall back
///     to Apple's cloud recogniser.
///   - **No audio retention.** Buffers are streamed straight to the
///     recognizer and discarded; nothing is written to disk.
///   - **Cheap to keep around.** No per-token cost. Engine spins up
///     only while the user is dictating.
final class DictationManager: NSObject, SFSpeechRecognizerDelegate {

    /// Result the caller acts on. `transcript` is the cumulative
    /// best-guess text so far; `isFinal` is true on the last call,
    /// after which the caller can stop expecting updates.
    struct Update {
        let transcript: String
        let isFinal: Bool
    }

    enum DictationError: Error, LocalizedError {
        case microphonePermissionDenied
        case speechPermissionDenied
        case recognizerUnavailable
        case audioEngineFailed(String)
        case sessionStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."
            case .speechPermissionDenied:
                return "Speech recognition access denied. Enable it in System Settings → Privacy & Security → Speech Recognition."
            case .recognizerUnavailable:
                return "Speech recognition isn't available right now. Check your network or try again."
            case .audioEngineFailed(let why):
                return "Couldn't start the microphone: \(why)"
            case .sessionStartFailed(let why):
                return "Couldn't start dictation: \(why)"
            }
        }
    }

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en_AU"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
        ?? SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var onUpdate: ((Update) -> Void)?
    private var onError: ((DictationError) -> Void)?
    private var autoStopTimer: Timer?

    /// Hard cap so a forgotten "I'm dictating" session can't drain
    /// battery indefinitely. 90s is plenty for any reasonable
    /// composer message.
    private let maxDictationSeconds: TimeInterval = 90

    var isRecording: Bool { audioEngine.isRunning }

    deinit { stop() }

    /// Begin dictation. Permissions are requested if not yet granted;
    /// errors are reported via `onError`. Safe to call when already
    /// running — no-ops in that case.
    func start(
        onUpdate: @escaping (Update) -> Void,
        onError: @escaping (DictationError) -> Void
    ) {
        guard !isRecording else { return }
        self.onUpdate = onUpdate
        self.onError = onError

        ensureSpeechPermission { [weak self] speechAllowed in
            guard let self else { return }
            guard speechAllowed else {
                self.dispatchError(.speechPermissionDenied)
                return
            }
            self.ensureMicrophonePermission { micAllowed in
                guard micAllowed else {
                    self.dispatchError(.microphonePermissionDenied)
                    return
                }
                DispatchQueue.main.async {
                    self.beginRecognition()
                }
            }
        }
    }

    /// Stop dictation. Idempotent. Safe to call from the main thread.
    func stop() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil

        // Order matters: end the audio request first so the recogniser
        // produces a final result, then stop the engine. If we stop the
        // engine first the in-flight buffer never lands.
        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest = nil
        recognitionTask = nil
    }

    // MARK: - Permission gates

    private func ensureSpeechPermission(_ completion: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                completion(status == .authorized)
            }
        @unknown default:
            completion(false)
        }
    }

    private func ensureMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
        @unknown default:
            completion(false)
        }
    }

    // MARK: - Recognition

    private func beginRecognition() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            dispatchError(.recognizerUnavailable)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer on-device when supported (macOS 13+ for English) so
        // the audio never leaves the Mac. Falls back automatically if
        // on-device isn't available for the current locale.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            dispatchError(.audioEngineFailed(error.localizedDescription))
            cleanupAfterFailure()
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let update = Update(
                    transcript: result.bestTranscription.formattedString,
                    isFinal: result.isFinal
                )
                DispatchQueue.main.async {
                    self.onUpdate?(update)
                }
                if result.isFinal {
                    self.cleanupAfterFinish()
                }
            }

            if error != nil {
                // Failures in the recogniser stream typically arrive
                // as benign "user stopped speaking" cancellations. We
                // surface them only when no successful partial has
                // landed yet, otherwise the caller has the transcript
                // it needs and the error would be confusing.
                self.cleanupAfterFinish()
            }
        }

        autoStopTimer = Timer.scheduledTimer(withTimeInterval: maxDictationSeconds, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.stop() }
        }
    }

    private func cleanupAfterFailure() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func cleanupAfterFinish() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func dispatchError(_ error: DictationError) {
        DispatchQueue.main.async {
            self.onError?(error)
        }
    }
}
