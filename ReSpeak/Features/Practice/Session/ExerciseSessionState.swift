// ExerciseSessionState.swift
// ReSpeak
//
// Value type capturing the full lifecycle state of an exercise session.
// Owned and mutated exclusively by ExerciseSessionEngine; published upward
// to ExerciseSessionViewModel for the UI to consume.
//
// No UIKit or SwiftUI imports — this file must remain UI-free.

import Foundation

// MARK: - SessionPhase

/// The lifecycle phase of a running exercise session.
/// The engine drives transitions; the view renders each phase differently.
public enum SessionPhase: Equatable, Sendable {

    /// Session has been created but items have not yet loaded.
    case loading

    /// Items are loaded; the user is working through prompts.
    /// - Parameter itemIndex: The zero-based index of the currently active item.
    case active(itemIndex: Int)

    /// The user is recording audio for the current item.
    case recording

    /// A recording was just completed; uploading/logging is in progress.
    case submitting

    /// All items have been completed and the session has been marked complete.
    case completed

    /// An unrecoverable error occurred. The message is safe to display.
    case failed(message: String)

    // MARK: Equatable

    public static func == (lhs: SessionPhase, rhs: SessionPhase) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading):
            return true
        case (.active(let a), .active(let b)):
            return a == b
        case (.recording, .recording):
            return true
        case (.submitting, .submitting):
            return true
        case (.completed, .completed):
            return true
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - ExerciseSessionState

/// Immutable snapshot of session progress, shared between the engine and UI.
/// All state changes are produced by replacing this struct wholesale so that
/// SwiftUI diffs are clean and predictable.
public struct ExerciseSessionState: Equatable, Sendable {

    // MARK: - Identity

    /// The unique ID of the `exercise_sessions` row in Supabase.
    public let sessionId: UUID

    /// The UUID of the `exercise_definitions` row being practised.
    public let exerciseDefinitionId: UUID

    /// Human-readable title of the exercise (used in the navigation bar).
    public let exerciseTitle: String

    // MARK: - Items

    /// The ordered array of prompts for this exercise.
    public let items: [ExerciseItem]

    /// Zero-based index of the item the user is currently on.
    public let currentItemIndex: Int

    // MARK: - Attempt Tracking

    /// Number of recording attempts the user has made on the current item.
    public let attemptsOnCurrentItem: Int

    // MARK: - Lifecycle

    /// Current phase of the session lifecycle.
    public let phase: SessionPhase

    // MARK: - Computed Properties

    /// Total number of items in the session.
    public var totalItems: Int { items.count }

    /// The item the user is currently working on, or nil during load/completion.
    public var currentItem: ExerciseItem? {
        guard items.indices.contains(currentItemIndex) else { return nil }
        return items[currentItemIndex]
    }

    /// Fractional progress through the session (0.0 – 1.0).
    /// Returns 1.0 when the session is complete.
    public var progress: Double {
        guard totalItems > 0 else { return 0 }
        switch phase {
        case .completed:
            return 1.0
        default:
            // Count the current item as partially complete while it's active.
            return Double(currentItemIndex) / Double(totalItems)
        }
    }

    /// Human-readable progress label, e.g. "3 of 10".
    public var displayProgress: String {
        guard totalItems > 0 else { return "" }
        switch phase {
        case .completed:
            return "\(totalItems) of \(totalItems)"
        default:
            return "\(currentItemIndex + 1) of \(totalItems)"
        }
    }

    /// `true` when the user is on the last item of the exercise.
    public var isLastItem: Bool {
        guard totalItems > 0 else { return false }
        return currentItemIndex == totalItems - 1
    }

    /// `true` when recording or submitting (controls UI button states).
    public var isBusy: Bool {
        switch phase {
        case .recording, .submitting, .loading:
            return true
        default:
            return false
        }
    }

    // MARK: - Init

    /// Designated initialiser. Prefer the static factory methods below for
    /// constructing canonical states.
    public init(
        sessionId: UUID,
        exerciseDefinitionId: UUID,
        exerciseTitle: String,
        items: [ExerciseItem],
        currentItemIndex: Int = 0,
        attemptsOnCurrentItem: Int = 0,
        phase: SessionPhase = .loading
    ) {
        self.sessionId              = sessionId
        self.exerciseDefinitionId   = exerciseDefinitionId
        self.exerciseTitle          = exerciseTitle
        self.items                  = items
        self.currentItemIndex       = currentItemIndex
        self.attemptsOnCurrentItem  = attemptsOnCurrentItem
        self.phase                  = phase
    }

    // MARK: - Mutation Helpers

    /// Returns a new state advanced to the next item.
    /// The caller is responsible for verifying `!isLastItem` before calling.
    func advancing() -> ExerciseSessionState {
        ExerciseSessionState(
            sessionId: sessionId,
            exerciseDefinitionId: exerciseDefinitionId,
            exerciseTitle: exerciseTitle,
            items: items,
            currentItemIndex: currentItemIndex + 1,
            attemptsOnCurrentItem: 0,
            phase: .active(itemIndex: currentItemIndex + 1)
        )
    }

    /// Returns a new state with the phase replaced.
    func withPhase(_ newPhase: SessionPhase) -> ExerciseSessionState {
        ExerciseSessionState(
            sessionId: sessionId,
            exerciseDefinitionId: exerciseDefinitionId,
            exerciseTitle: exerciseTitle,
            items: items,
            currentItemIndex: currentItemIndex,
            attemptsOnCurrentItem: attemptsOnCurrentItem,
            phase: newPhase
        )
    }

    /// Returns a new state with the attempt counter incremented.
    func incrementingAttempts() -> ExerciseSessionState {
        ExerciseSessionState(
            sessionId: sessionId,
            exerciseDefinitionId: exerciseDefinitionId,
            exerciseTitle: exerciseTitle,
            items: items,
            currentItemIndex: currentItemIndex,
            attemptsOnCurrentItem: attemptsOnCurrentItem + 1,
            phase: phase
        )
    }
}
