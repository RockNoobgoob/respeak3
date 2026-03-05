// ExerciseSessionViewModel.swift
// ReSpeak
//
// @MainActor ObservableObject that owns an ExerciseSessionEngine and bridges
// its state into SwiftUI-friendly @Published properties. This is the single
// source of truth for ExerciseSessionView and any exercise-specific overlays.
//
// Usage:
//   let vm = ExerciseSessionViewModel(exercise: selectedExercise)
//   ExerciseSessionView(viewModel: vm) { state in
//       MyExerciseContent(state: state)
//   }

import Foundation

// MARK: - ExerciseSessionViewModel

@MainActor
final class ExerciseSessionViewModel: ObservableObject {

    // MARK: - Published State

    /// The latest snapshot of session progress.
    /// Subscribe to drive progress bars, item prompts, and phase-gated controls.
    @Published private(set) var state: ExerciseSessionState

    /// `true` while the audio recorder is capturing audio.
    /// Drives mic button icon toggle and disables other controls.
    @Published private(set) var isRecording: Bool = false

    /// `true` during async work (session start, attempt upload, finish).
    /// Drives the loading overlay in the view.
    @Published private(set) var isLoading: Bool = false

    /// Non-nil when an actionable error has occurred.
    /// Presented as an `.alert` in the view; cleared when the user dismisses.
    @Published var errorMessage: String?

    /// Becomes `true` after `finishSession()` completes.
    /// `ExerciseSessionView` observes this to dismiss the sheet or navigate back.
    @Published private(set) var sessionComplete: Bool = false

    /// `true` while a recording has been captured but not yet submitted.
    /// Enables the "Submit Recording" button in the view.
    @Published private(set) var hasUnsubmittedRecording: Bool = false

    // MARK: - Engine

    private let engine: ExerciseSessionEngine

    // MARK: - Configuration

    private let exercise: ExerciseDefinition

    // MARK: - Init

    /// - Parameters:
    ///   - exercise: The `ExerciseDefinition` selected by the user.
    ///     Items are resolved by the engine (re-fetched if empty).
    ///   - engine: Optional custom engine for testing; defaults to a new instance
    ///     wired to the shared repositories and auth service.
    init(
        exercise: ExerciseDefinition,
        engine: ExerciseSessionEngine? = nil
    ) {
        self.exercise = exercise
        self.engine   = engine ?? ExerciseSessionEngine()

        // Seed a loading placeholder so the view has a valid (non-optional) state
        // from the very first render, before `start()` is called.
        self.state = ExerciseSessionState(
            sessionId: UUID(),
            exerciseDefinitionId: exercise.id,
            exerciseTitle: exercise.title,
            items: [],
            phase: .loading
        )

        // Wire the engine's state changes back into @Published.
        self.engine.onStateChange = { [weak self] newState in
            guard let self else { return }
            self.applyState(newState)
        }
    }

    // MARK: - Public API

    /// Fetches exercise items and creates the Supabase session row.
    /// Call this from `.task` in the view so it starts immediately on appear.
    func start() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await engine.startSession(exercise: exercise)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Starts audio recording for the current item.
    ///
    /// - Parameter maxDuration: Recording cap in seconds.
    ///   Defaults to 30 s — override per exercise type by passing a custom value.
    ///
    /// TODO: Plug in exercise-specific logic here — some exercises may start
    ///       recording automatically (e.g. shadowing tasks).
    func startRecording(maxDuration: TimeInterval = 30) {
        guard !isRecording else { return }
        Task {
            do {
                try await engine.startRecording(maxDuration: maxDuration)
                isRecording = true
                hasUnsubmittedRecording = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Stops the active recording. The file is held in memory until the user
    /// either submits or discards it.
    func stopRecording() {
        guard isRecording else { return }
        engine.stopRecording()
        isRecording = false
        hasUnsubmittedRecording = true
    }

    /// Toggles recording on/off. Wired to the mic button in the view.
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// Uploads the last recording and logs the attempt, then advances or finishes.
    ///
    /// If this is the last item the session is automatically completed after
    /// the attempt is submitted, removing one tap for the user.
    func submitRecording() {
        guard
            hasUnsubmittedRecording,
            let item = state.currentItem
        else { return }

        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await engine.submitAttempt(currentItemId: item.id)
                hasUnsubmittedRecording = false

                // Auto-advance after a successful submission.
                if state.isLastItem {
                    try await engine.finishSession()
                } else {
                    engine.nextItem()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Advances to the next item without submitting a recording.
    /// Use only when the exercise type allows skipping.
    ///
    /// TODO: Plug in exercise-specific logic here — enforce attempt requirements
    ///       before allowing advancement (e.g. must attempt at least once).
    func advance() {
        if state.isLastItem {
            finishSession()
        } else {
            engine.nextItem()
        }
    }

    /// Marks the session complete in Supabase without requiring a recording submit.
    /// Called by `advance()` when on the last item, or directly by the view's
    /// "Finish" button.
    func finishSession() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await engine.finishSession()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Returns the current microphone power level (dBFS) for waveform animations.
    /// Returns `nil` when not recording.
    func currentMicPower() -> Float? {
        engine.currentAveragePower()
    }

    // MARK: - Private

    /// Translates engine state into ViewModel-level derived properties.
    private func applyState(_ newState: ExerciseSessionState) {
        state = newState

        // Sync isRecording from phase so engine-driven stops
        // (e.g. maxDuration elapsed) are reflected in the UI.
        switch newState.phase {
        case .recording:
            isRecording = true
        case .active, .loading, .submitting, .failed:
            isRecording = false
        case .completed:
            isRecording = false
            sessionComplete = true
        }
    }
}
