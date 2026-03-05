// ExerciseSessionEngine.swift
// ReSpeak
//
// Pure session logic layer: orchestrates AVAudioRecorder, the recording
// timer, and all Supabase writes for a single exercise session.
// This class is intentionally decoupled from SwiftUI — it publishes state
// upward to ExerciseSessionViewModel via an AsyncStream.
//
// Individual exercise types plug in by observing ExerciseSessionState and
// rendering their own content inside ExerciseSessionView's generic slot.
// See: ExerciseSessionView.swift → `exerciseContent` ViewBuilder.

import Foundation
import AVFoundation

// MARK: - SessionEngineError

/// Errors raised by `ExerciseSessionEngine`.
/// All cases produce a localised string safe to display in the UI.
public enum SessionEngineError: LocalizedError {

    case notAuthenticated
    case itemsEmpty
    case recordingSetupFailed(underlying: Error)
    case recordingNotStarted
    case audioDataMissing(url: URL)
    case uploadFailed(underlying: Error)
    case sessionCompletionFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to start a session."
        case .itemsEmpty:
            return "This exercise has no items to practice. Please contact your clinician."
        case .recordingSetupFailed(let e):
            return "Could not set up the microphone: \(e.localizedDescription)"
        case .recordingNotStarted:
            return "No recording is in progress."
        case .audioDataMissing(let url):
            return "Could not read the recording file at \(url.lastPathComponent)."
        case .uploadFailed(let e):
            return "Could not upload your recording: \(e.localizedDescription)"
        case .sessionCompletionFailed(let e):
            return "Could not mark the session complete: \(e.localizedDescription)"
        }
    }
}

// MARK: - ExerciseSessionEngine

/// Drives the full lifecycle of one exercise session.
///
/// Responsibilities:
/// - Manages `AVAudioRecorder` for on-device recording.
/// - Coordinates uploads via `RecordingRepository`.
/// - Logs attempts via `SessionRepository`.
/// - Publishes `ExerciseSessionState` to the ViewModel through a continuation.
///
/// Threading: all public methods are `async` and safe to call from
/// `@MainActor` contexts. Internal audio work happens on a `Task` and is
/// synchronised through the `AVAudioRecorder` callbacks.
@MainActor
final class ExerciseSessionEngine: NSObject {

    // MARK: - Dependencies

    private let sessionRepo: SessionRepository
    private let recordingRepo: RecordingRepository
    private let auth: AuthService
    private let exerciseRepo: ExerciseRepository

    // MARK: - Published State (stream)

    /// Receive state updates by iterating `stateUpdates` in the ViewModel.
    private(set) var currentState: ExerciseSessionState

    /// Callback invoked each time the state is mutated.
    /// The ViewModel assigns this closure to bridge into `@Published`.
    var onStateChange: ((ExerciseSessionState) -> Void)?

    // MARK: - Audio

    private var audioRecorder: AVAudioRecorder?
    private var activeRecordingURL: URL?
    private var recordingTimer: Timer?

    // MARK: - Init

    init(
        sessionRepo: SessionRepository   = RepositoryContainer.shared.sessions,
        recordingRepo: RecordingRepository = RepositoryContainer.shared.recordings,
        auth: AuthService                = ServiceContainer.shared.auth,
        exerciseRepo: ExerciseRepository = RepositoryContainer.shared.exercises,
        // Placeholder state; replaced by startSession before the view renders.
        placeholderState: ExerciseSessionState = ExerciseSessionState(
            sessionId: UUID(),
            exerciseDefinitionId: UUID(),
            exerciseTitle: "",
            items: []
        )
    ) {
        self.sessionRepo    = sessionRepo
        self.recordingRepo  = recordingRepo
        self.auth           = auth
        self.exerciseRepo   = exerciseRepo
        self.currentState   = placeholderState
        super.init()
    }

    // MARK: - Session Lifecycle

    /// Fetches items for the exercise and creates a new session row in Supabase.
    ///
    /// Call this once when navigating into the session screen.
    ///
    /// - Parameters:
    ///   - exercise: The `ExerciseDefinition` the user selected. Items are read
    ///     from `exercise.items`; if empty the engine fetches the definition
    ///     again to ensure items are populated.
    /// - Throws: `SessionEngineError` on auth or Supabase failure.
    func startSession(exercise: ExerciseDefinition) async throws {
        let userId = try requireUserId()
        publish(currentState.withPhase(.loading))

        // Ensure items are loaded — PracticeViewModel may have fetched without
        // joining items, so re-fetch via ExerciseRepository when needed.
        let resolvedExercise: ExerciseDefinition
        if exercise.items.isEmpty {
            resolvedExercise = try await exerciseRepo.fetchExercise(id: exercise.id)
        } else {
            resolvedExercise = exercise
        }

        guard !resolvedExercise.items.isEmpty else {
            throw SessionEngineError.itemsEmpty
        }

        // Sort items by their display order so the sequence is deterministic.
        let sortedItems = resolvedExercise.items.sorted { $0.orderIndex < $1.orderIndex }

        // Create the Supabase session row.
        let session = try await sessionRepo.createSession(
            exerciseId: exercise.id,
            userId: userId
        )

        let initialState = ExerciseSessionState(
            sessionId: session.id,
            exerciseDefinitionId: exercise.id,
            exerciseTitle: exercise.title,
            items: sortedItems,
            currentItemIndex: 0,
            attemptsOnCurrentItem: 0,
            phase: .active(itemIndex: 0)
        )
        publish(initialState)
    }

    // MARK: - Item Navigation

    /// Advances the session to the next item.
    ///
    /// Must only be called while `phase == .active` and `!isLastItem`.
    /// The ViewModel should call `finishSession()` instead when on the last item.
    func nextItem() {
        guard !currentState.isLastItem else { return }
        publish(currentState.advancing())
    }

    // MARK: - Recording

    /// Configures `AVAudioSession` and starts recording to a temporary file.
    ///
    /// - Parameter maxDuration: Maximum recording length in seconds. The
    ///   recorder is automatically stopped when this elapses. Pass `0` or
    ///   `nil` for unlimited recording (user must tap stop manually).
    ///
    /// TODO: Plug in exercise-specific logic here — e.g. some exercise types
    ///       may want to start recording automatically or impose different limits.
    func startRecording(maxDuration: TimeInterval = 30) async throws {
        try configureAudioSession()

        let url = temporaryRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey:         Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey:       44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            if maxDuration > 0 {
                recorder.record(forDuration: maxDuration)
            } else {
                recorder.record()
            }
            self.audioRecorder     = recorder
            self.activeRecordingURL = url
            publish(currentState.withPhase(.recording))
        } catch {
            throw SessionEngineError.recordingSetupFailed(underlying: error)
        }
    }

    /// Stops any active recording and returns the local file URL.
    ///
    /// Returns `nil` if no recording was in progress.
    @discardableResult
    func stopRecording() -> URL? {
        guard let recorder = audioRecorder, recorder.isRecording else { return nil }
        recorder.stop()
        return activeRecordingURL
    }

    // MARK: - Attempt Submission

    /// Stops the current recording, uploads it to Supabase Storage, and logs
    /// the attempt in `exercise_attempts`.
    ///
    /// Transitions the phase to `.submitting` while work is in progress and
    /// back to `.active` on completion (or `.failed` on error).
    ///
    /// TODO: Plug in exercise-specific logic here — e.g. trigger AI scoring
    ///       or on-device analysis immediately after the upload completes.
    ///
    /// - Parameter currentItemId: The UUID of the item the attempt belongs to.
    func submitAttempt(currentItemId: UUID) async throws {
        let userId = try requireUserId()
        let sessionId = currentState.sessionId

        // Stop recording and grab the local file URL.
        guard let localURL = stopRecording() else {
            throw SessionEngineError.recordingNotStarted
        }

        publish(currentState.withPhase(.submitting))

        defer {
            // Always clean up the temp file, even on error paths.
            cleanUpTemporaryFile(at: localURL)
        }

        // Read raw bytes from the temp file.
        guard let audioData = try? Data(contentsOf: localURL) else {
            throw SessionEngineError.audioDataMissing(url: localURL)
        }

        // 1. Log the attempt row first (without a recording URL) so we have
        //    an ID to use as the storage path segment.
        let attemptInsert = AttemptInsert(
            session_id: sessionId.uuidString,
            exercise_item_id: currentItemId.uuidString,
            recording_url: nil,
            rating: nil
        )
        let attempt = try await sessionRepo.logAttempt(attemptInsert)

        // 2. Upload the audio file.
        do {
            let publicURL = try await recordingRepo.uploadRecording(
                data: audioData,
                userId: userId,
                sessionId: sessionId,
                attemptId: attempt.id
            )

            // 3. Update the attempt row with the storage URL.
            try await recordingRepo.updateAttemptRecordingURL(
                attemptId: attempt.id,
                url: publicURL
            )
        } catch {
            // Upload is best-effort; the attempt row is already logged.
            // Surface the error but do not block progression.
            throw SessionEngineError.uploadFailed(underlying: error)
        }

        // Restore active phase with incremented attempt counter.
        publish(currentState.incrementingAttempts().withPhase(
            .active(itemIndex: currentState.currentItemIndex)
        ))
    }

    // MARK: - Session Completion

    /// Stamps `completed_at` on the session row and transitions to `.completed`.
    ///
    /// Call this after the user taps "Finish" on the last item.
    func finishSession() async throws {
        do {
            try await sessionRepo.completeSession(sessionId: currentState.sessionId)
            publish(currentState.withPhase(.completed))
        } catch {
            throw SessionEngineError.sessionCompletionFailed(underlying: error)
        }
    }

    // MARK: - Audio Metering

    /// Returns the current average power in dBFS, or `nil` if not recording.
    /// Callers should invoke this on a polling `Timer` to animate a VU meter.
    func currentAveragePower() -> Float? {
        guard let recorder = audioRecorder, recorder.isRecording else { return nil }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }

    // MARK: - Private Helpers

    private func requireUserId() throws -> UUID {
        try auth.requireUserId()
    }

    private func publish(_ state: ExerciseSessionState) {
        currentState = state
        onStateChange?(state)
    }

    /// Configures `AVAudioSession` for recording with speaker playback.
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // `.playAndRecord` allows both recording and playback (for review).
            // `.defaultToSpeaker` ensures audio is routed to the main speaker
            // when no headphones are connected, which is the expected therapy UX.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            throw SessionEngineError.recordingSetupFailed(underlying: error)
        }
    }

    /// Deactivates the audio session when not in use to release the microphone
    /// and allow other apps (e.g. music) to resume.
    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Returns a unique URL in the system temp directory for each recording.
    private func temporaryRecordingURL() -> URL {
        let fileName = "respeak_recording_\(UUID().uuidString).m4a"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }

    /// Removes a temporary recording file after a successful upload.
    private func cleanUpTemporaryFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        activeRecordingURL = nil
        audioRecorder = nil
        deactivateAudioSession()
    }
}

// MARK: - AVAudioRecorderDelegate

extension ExerciseSessionEngine: AVAudioRecorderDelegate {

    /// Called when the recorder stops — either by the user or because
    /// `maxDuration` elapsed. Transition back to `.active` so the user
    /// can review and submit or re-record.
    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            guard flag else {
                self.publish(
                    self.currentState.withPhase(
                        .failed(message: "Recording stopped unexpectedly. Please try again.")
                    )
                )
                return
            }
            // Recording finished successfully; move back to active so the
            // user can choose to submit or re-record.
            self.publish(
                self.currentState.withPhase(
                    .active(itemIndex: self.currentState.currentItemIndex)
                )
            )
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        let message = error?.localizedDescription ?? "Unknown encoding error."
        Task { @MainActor in
            self.publish(self.currentState.withPhase(.failed(message: message)))
        }
    }
}
