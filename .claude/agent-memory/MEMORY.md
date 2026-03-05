# ReSpeak Agent Memory

See topic files for details. Key facts that fit in this summary:

## Architecture
- Feature folder: `ReSpeak/Features/<Feature>/`
- Session layer lives at `ReSpeak/Features/Practice/Session/`
- Four-layer stack per feature: State → Engine → ViewModel → View
- `ExerciseSessionEngine` is `@MainActor final class` (NOT an actor) so
  AVAudioRecorderDelegate can bridge back via `Task { @MainActor in ... }`

## Supabase Tables
- `exercise_definitions` — exercise metadata (joined with `exercise_items`)
- `exercise_items` — individual prompts; CodingKey alias `"exercise_items"`
- `exercise_sessions` — session rows; completed via `completed_at` timestamp
- `exercise_attempts` — one row per recording; `recording_url` patched after upload
- Storage bucket: `recordings`, path: `{userId}/{sessionId}/{attemptId}.m4a`

## Repositories & Services (all use SupabaseService.shared)
- `ExerciseRepository` — fetch definitions + items (joined select)
- `SessionRepository` — createSession / logAttempt / completeSession
- `RecordingRepository` — uploadRecording / updateAttemptRecordingURL
- `AuthService` — `requireUserId()` throws `ReSpeakError.notAuthenticated`
- Access via `RepositoryContainer.shared.*` and `ServiceContainer.shared.*`

## Design Tokens (confirmed)
- Colors: `BrandColors.*` — primary=#1A3C5E, secondary=#2E6DA4, accent=#00B4D8
- Typography: `BrandTypography.*` + `.brandStyle(_:)` modifier
- Spacing: `Spacing.*` — xxs=4, xs=8, sm=12, md=16, lg=24, xl=32, xxl=48, xxxl=64
  - Aliases: `.screenHorizontal=md`, `.sectionGap=lg`, `.cardPadding=md`, `.rowPadding=sm`
- Radii: `Radii.*` — card=16, button=12, input=8, sheet=24, pill=999
- Shadows: `.cardShadow()`, `.elevatedShadow()`, `.floatingShadow()` modifiers
- Gradients: `BrandGradients.primaryGradient`, `.buttonGradient`, `.successGradient`, etc.

## AVAudioSession
- Category: `.playAndRecord`, mode: `.default`, options: `[.defaultToSpeaker]`
- Deactivate with `.notifyOthersOnDeactivation` when not recording
- Format: MPEG4AAC, 44100 Hz, mono, high quality → `.m4a` extension

## PracticeView Navigation Pattern
- `.fullScreenCover(item: $sessionExercise)` drives session presentation
- `sessionExercise: ExerciseDefinition?` is the trigger state variable
- Close button in session toolbar sets `sessionExercise = nil`
- `ExerciseSessionViewModel` creates its own session row — do NOT call
  `PracticeViewModel.selectExercise()` when launching via the new flow

## Generic Content Injection
- `ExerciseSessionView<Content: View>` accepts `@ViewBuilder exerciseContent: (ExerciseSessionState) -> Content`
- Exercise-type views inspect `state.currentItem?.payload` for config
- Category/type routing TODO lives in PracticeView's fullScreenCover stub

See `exercise-session-engine/patterns.md` for deeper notes.
