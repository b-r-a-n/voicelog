import Foundation
import Speech
import AVFoundation

struct TranscriptionResult {
    let transcript: String
    let duration: TimeInterval
    let isFinal: Bool
}

protocol SpeechRecognitionStrategy {
    var isRecording: Bool { get }
    func startRecording() async throws
    func stopRecording() async throws -> TranscriptionResult
    var transcriptPublisher: AsyncStream<String> { get }
}

@MainActor
final class SpeechService: ObservableObject {
    static let shared = SpeechService()

    @Published private(set) var isRecording = false
    @Published private(set) var currentTranscript = ""
    @Published private(set) var recordingDuration: TimeInterval = 0
    @Published var error: Error?

    private var strategy: SpeechRecognitionStrategy?
    private var transcriptTask: Task<Void, Never>?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?

    private init() {}

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else { return false }

        let audioStatus = await AVAudioApplication.requestRecordPermission()
        return audioStatus
    }

    func startRecording() async throws {
        guard !isRecording else { return }

        let hasPermissions = await requestPermissions()
        guard hasPermissions else {
            throw SpeechError.permissionDenied
        }

        // Use legacy speech recognition strategy
        // Note: SpeechAnalyzer API for iOS 26+ is not yet available
        strategy = LegacySpeechStrategy()

        guard let strategy else {
            throw SpeechError.initializationFailed
        }

        try await strategy.startRecording()
        isRecording = true
        currentTranscript = ""
        recordingStartTime = Date()

        // Start duration timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }

        // Listen for transcript updates
        transcriptTask = Task {
            for await transcript in strategy.transcriptPublisher {
                self.currentTranscript = transcript
            }
        }
    }

    func stopRecording() async throws -> TranscriptionResult {
        guard isRecording, let strategy else {
            throw SpeechError.notRecording
        }

        durationTimer?.invalidate()
        durationTimer = nil
        transcriptTask?.cancel()
        transcriptTask = nil

        let result = try await strategy.stopRecording()
        isRecording = false
        self.strategy = nil

        return result
    }

    func cancelRecording() {
        durationTimer?.invalidate()
        durationTimer = nil
        transcriptTask?.cancel()
        transcriptTask = nil
        isRecording = false
        currentTranscript = ""
        recordingDuration = 0
        strategy = nil
    }
}

enum SpeechError: Error, LocalizedError {
    case permissionDenied
    case initializationFailed
    case notRecording
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Speech recognition permission denied"
        case .initializationFailed:
            return "Failed to initialize speech recognition"
        case .notRecording:
            return "Not currently recording"
        case .recognitionFailed(let error):
            return "Recognition failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Speech Recognition Strategy using SFSpeechRecognizer

final class LegacySpeechStrategy: SpeechRecognitionStrategy {
    private(set) var isRecording = false
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var transcriptContinuation: AsyncStream<String>.Continuation?
    private var accumulatedTranscript = ""
    private var recordingStart: Date?

    // Session chaining for long recordings
    private var sessionStartTime: Date?
    private let maxSessionDuration: TimeInterval = 55  // ~55 seconds before session limit
    private var sessionRestartTask: Task<Void, Never>?

    var transcriptPublisher: AsyncStream<String> {
        AsyncStream { continuation in
            self.transcriptContinuation = continuation
        }
    }

    func startRecording() async throws {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechError.initializationFailed
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        audioEngine = AVAudioEngine()
        accumulatedTranscript = ""
        recordingStart = Date()

        try await startRecognitionSession()
        isRecording = true
    }

    private func startRecognitionSession() async throws {
        guard let audioEngine, let speechRecognizer else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { throw SpeechError.initializationFailed }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Remove existing tap if any
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        sessionStartTime = Date()

        let sessionStartTranscript = accumulatedTranscript

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let newText = result.bestTranscription.formattedString
                self.accumulatedTranscript = sessionStartTranscript.isEmpty
                    ? newText
                    : sessionStartTranscript + " " + newText
                self.transcriptContinuation?.yield(self.accumulatedTranscript)
            }

            if error != nil || result?.isFinal == true {
                // Session ended, restart if still recording
                if self.isRecording {
                    Task {
                        try? await self.restartSession()
                    }
                }
            }
        }

        // Schedule session restart before timeout
        sessionRestartTask?.cancel()
        sessionRestartTask = Task {
            try? await Task.sleep(for: .seconds(maxSessionDuration))
            if self.isRecording {
                try? await self.restartSession()
            }
        }
    }

    private func restartSession() async throws {
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        audioEngine?.inputNode.removeTap(onBus: 0)

        // Small delay to allow cleanup
        try? await Task.sleep(for: .milliseconds(100))

        if isRecording {
            try await startRecognitionSession()
        }
    }

    func stopRecording() async throws -> TranscriptionResult {
        sessionRestartTask?.cancel()
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        transcriptContinuation?.finish()

        let duration = recordingStart.map { Date().timeIntervalSince($0) } ?? 0
        isRecording = false

        return TranscriptionResult(
            transcript: accumulatedTranscript,
            duration: duration,
            isFinal: true
        )
    }
}
