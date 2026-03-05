# Exercise Session Engine — Patterns & Decisions

## State Machine (SessionPhase)

Phases: loading → active(itemIndex:) ↔ recording → submitting → active / completed / failed

Key: `ExerciseSessionState` is a struct replaced wholesale on every transition
(not mutated in-place). This makes SwiftUI diffs clean and the phase history
trivially debuggable.

## Engine Threading Model

`ExerciseSessionEngine` is `@MainActor final class NSObject`.

Why NOT `actor`:
- `AVAudioRecorderDelegate` methods are `nonisolated` by default, so they
  need `Task { @MainActor in ... }` to post back. This works cleanly with
  a `@MainActor class` but would require extra `await` hops from an `actor`.

## ViewModel ↔ Engine Bridge

The engine exposes `var onStateChange: ((ExerciseSessionState) -> Void)?`.
The ViewModel assigns a closure in `init`:

```swift
engine.onStateChange = { [weak self] newState in
    self?.applyState(newState)
}
```

`applyState` derives `isRecording`, `sessionComplete` etc. from the phase enum
rather than storing redundant flags. This prevents desync bugs.

## Attempt Flow (order matters)

1. `engine.stopRecording()` → returns local URL
2. `sessionRepo.logAttempt(AttemptInsert)` → returns `ExerciseAttempt` with DB-generated UUID
3. `recordingRepo.uploadRecording(data:userId:sessionId:attemptId:)` → returns public URL
4. `recordingRepo.updateAttemptRecordingURL(attemptId:url:)` — patches the attempt row
5. Temp file deleted via `cleanUpTemporaryFile(at:)` in `defer`

Step 2 before 3 is intentional — we need the `attempt.id` to build the storage path
(`{userId}/{sessionId}/{attemptId}.m4a`), and the row must exist for the FK in storage RLS.

## ExerciseItem Sorting

Items fetched via join are NOT guaranteed to arrive in `order_index` order
(Supabase join order is not deterministic). Always sort:

```swift
let sortedItems = exercise.items.sorted { $0.orderIndex < $1.orderIndex }
```

## Empty Items Guard

`ExerciseRepository.fetchExercise(id:)` always joins items. However, when
`PracticeViewModel` calls `fetchExercises()` (the list endpoint), items ARE
joined (confirmed from ExerciseRepository.swift select string). Despite this,
the engine re-fetches via `fetchExercise(id:)` if `exercise.items.isEmpty`
as a defensive measure — the list endpoint may be changed in future.

## Audio File Cleanup

`cleanUpTemporaryFile(at:)` is called in a `defer` block inside `submitAttempt`.
It fires even on throw paths, so temp files never accumulate regardless of
network errors.

## PracticeView Integration Note

`sessionExercise: ExerciseDefinition?` conforms to `Identifiable` (it has `id: UUID`),
so `.fullScreenCover(item:)` works without a custom `Identifiable` wrapper.

## TODO Extension Points (marked in code)

1. `ExerciseSessionEngine.startRecording()` — auto-start for shadowing exercises
2. `ExerciseSessionViewModel.submitRecording()` — enforce minimum attempt count
3. `ExerciseSessionViewModel.advance()` — gate advancement on attempt requirement
4. `ExerciseSessionEngine.submitAttempt()` — trigger AI scoring post-upload
5. `PracticeView` fullScreenCover stub — route by `exercise.category` to typed content views
6. `ExerciseSessionView` `exerciseContent` closure — read `state.currentItem?.payload`
