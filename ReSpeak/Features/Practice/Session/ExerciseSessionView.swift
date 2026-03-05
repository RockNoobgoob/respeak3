// ExerciseSessionView.swift
// ReSpeak
//
// Generic reusable session shell. Individual exercise types inject their
// own prompt UI through the `exerciseContent` ViewBuilder slot — they never
// need to re-implement progress tracking, the record button, or the
// loading/error overlay.
//
// Usage:
//   ExerciseSessionView(viewModel: vm) { state in
//       // Exercise-specific content rendered here:
//       SentenceRepeatContent(item: state.currentItem)
//   }

import SwiftUI

// MARK: - ExerciseSessionView

/// Generic session shell.
///
/// - `Content`: Any SwiftUI `View` produced by the `exerciseContent` closure.
///   The closure receives the current `ExerciseSessionState` so the injected
///   content can react to item changes without maintaining its own state.
struct ExerciseSessionView<Content: View>: View {

    // MARK: - ViewModel

    @ObservedObject var viewModel: ExerciseSessionViewModel

    // MARK: - Injected Exercise Content

    /// Closure that maps the current session state to an exercise-specific view.
    /// This is the primary extension point — every exercise type supplies its
    /// own implementation here.
    ///
    /// TODO: Exercise-specific views should observe `state.currentItem?.payload`
    ///       for type-specific configuration data stored in the database.
    @ViewBuilder let exerciseContent: (ExerciseSessionState) -> Content

    // MARK: - Private State

    /// Drives a simple repeating animation on the record button while active.
    @State private var isRecordPulsing = false

    /// Controls the error alert.
    @State private var showingError = false

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        ZStack {
            // Screen background
            BrandColors.background
                .ignoresSafeArea()

            VStack(spacing: .zero) {
                progressHeader
                    .padding(.horizontal, Spacing.screenHorizontal)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.sm)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.lg) {
                        promptCard
                        recordingControls
                        actionButton
                    }
                    .padding(.horizontal, Spacing.screenHorizontal)
                    .padding(.bottom, Spacing.xl)
                }
            }

            // Loading overlay — shown during session start and attempt upload.
            if viewModel.isLoading {
                loadingOverlay
            }
        }
        .navigationTitle(viewModel.state.exerciseTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isLoading)
        .task {
            viewModel.start()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("Dismiss", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onChange(of: viewModel.sessionComplete) { _, complete in
            if complete { dismiss() }
        }
    }

    // MARK: - Progress Header

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(viewModel.state.displayProgress)
                    .brandStyle(.caption1)

                Spacer()

                Text(attemptLabel)
                    .brandStyle(.caption1)
            }

            ProgressView(value: viewModel.state.progress)
                .tint(BrandColors.accent)
                .animation(.easeInOut(duration: 0.35), value: viewModel.state.progress)
        }
    }

    // MARK: - Prompt Card

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            phaseLabel

            // ── Exercise-specific content slot ──────────────────────────
            // Individual exercises render their prompts, illustrations,
            // or any custom UI inside this area.
            exerciseContent(viewModel.state)
                .frame(maxWidth: .infinity, alignment: .leading)
            // ────────────────────────────────────────────────────────────
        }
        .padding(Spacing.cardPadding)
        .background(BrandColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radii.card))
        .cardShadow()
        .padding(.top, Spacing.sm)
    }

    // MARK: - Phase Label

    /// Small contextual label above the exercise content indicating current phase.
    @ViewBuilder
    private var phaseLabel: some View {
        switch viewModel.state.phase {
        case .loading:
            HStack(spacing: Spacing.iconLabelGap) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading exercise…")
                    .brandStyle(.caption1)
            }
        case .active:
            Text("YOUR TURN")
                .font(BrandTypography.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(BrandColors.accent)
                .kerning(1.2)
        case .recording:
            HStack(spacing: Spacing.iconLabelGap) {
                Circle()
                    .fill(BrandColors.error)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isRecordPulsing ? 1.3 : 0.9)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                        value: isRecordPulsing
                    )
                    .onAppear { isRecordPulsing = true }
                    .onDisappear { isRecordPulsing = false }
                Text("RECORDING")
                    .font(BrandTypography.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(BrandColors.error)
                    .kerning(1.2)
            }
        case .submitting:
            HStack(spacing: Spacing.iconLabelGap) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Saving attempt…")
                    .brandStyle(.caption1)
            }
        case .completed:
            HStack(spacing: Spacing.iconLabelGap) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BrandColors.success)
                Text("Session complete!")
                    .brandStyle(.callout)
            }
        case .failed(let message):
            HStack(alignment: .top, spacing: Spacing.iconLabelGap) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BrandColors.error)
                Text(message)
                    .brandStyle(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Recording Controls

    private var recordingControls: some View {
        VStack(spacing: Spacing.md) {
            // Mic / Stop button
            Button(action: viewModel.toggleRecording) {
                ZStack {
                    Circle()
                        .fill(
                            viewModel.isRecording
                                ? BrandColors.error
                                : BrandColors.primary
                        )
                        .frame(width: 80, height: 80)
                        .shadow(
                            color: (viewModel.isRecording ? BrandColors.error : BrandColors.primary)
                                .opacity(0.30),
                            radius: viewModel.isRecording ? 20 : 10,
                            x: 0,
                            y: viewModel.isRecording ? 8 : 4
                        )
                        .scaleEffect(isRecordPulsing && viewModel.isRecording ? 1.06 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                                   value: isRecordPulsing && viewModel.isRecording)

                    Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(BrandColors.onPrimary)
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.state.isBusy && !viewModel.isRecording)
            .accessibilityLabel(viewModel.isRecording ? "Stop recording" : "Start recording")

            Text(recordButtonHint)
                .brandStyle(.footnote)
                .multilineTextAlignment(.center)
                .animation(.default, value: viewModel.isRecording)

            // Submit recording button — only visible when a recording is ready.
            if viewModel.hasUnsubmittedRecording {
                Button(action: viewModel.submitRecording) {
                    Label("Submit Recording", systemImage: "arrow.up.circle.fill")
                        .font(BrandTypography.button)
                        .foregroundStyle(BrandColors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(BrandGradients.successGradient)
                        .clipShape(RoundedRectangle(cornerRadius: Radii.button))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .cardShadow()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewModel.hasUnsubmittedRecording)
    }

    // MARK: - Action Button (Next / Finish)

    private var actionButton: some View {
        Button(action: viewModel.advance) {
            Text(viewModel.state.isLastItem ? "Finish Session" : "Next")
                .font(BrandTypography.button)
                .foregroundStyle(BrandColors.onPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    viewModel.state.isBusy
                        ? AnyShapeStyle(BrandColors.disabled)
                        : AnyShapeStyle(BrandGradients.buttonGradient)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radii.button))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.state.isBusy)
        .cardShadow()
        .accessibilityLabel(viewModel.state.isLastItem ? "Finish session" : "Next item")
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: Spacing.md) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(BrandColors.onPrimary)

                Text("Please wait…")
                    .brandStyle(.onPrimary)
            }
            .padding(Spacing.xl)
            .background(BrandColors.primary.opacity(0.90))
            .clipShape(RoundedRectangle(cornerRadius: Radii.card))
            .floatingShadow()
        }
        .transition(.opacity)
    }

    // MARK: - Helpers

    /// Contextual hint text below the mic button.
    private var recordButtonHint: String {
        if viewModel.isRecording {
            return "Tap to stop recording"
        } else if viewModel.hasUnsubmittedRecording {
            return "Tap to re-record, or submit above"
        } else {
            return "Tap to start recording"
        }
    }

    /// Attempt counter label shown in the progress header.
    private var attemptLabel: String {
        let count = viewModel.state.attemptsOnCurrentItem
        switch count {
        case 0:  return "First attempt"
        case 1:  return "1 attempt"
        default: return "\(count) attempts"
        }
    }
}

// MARK: - Preview

#Preview("Session Shell") {
    // Build a lightweight stub exercise for preview purposes.
    let stubItems: [ExerciseItem] = (1...5).map { i in
        ExerciseItem(
            id: UUID(),
            exerciseDefinitionId: UUID(),
            prompt: "Say the sentence: "The quick brown fox jumps over the lazy dog." (item \(i))",
            orderIndex: i,
            payload: nil,
            createdAt: Date()
        )
    }
    let stubExercise = ExerciseDefinition(
        id: UUID(),
        title: "Sentence Repetition",
        subtitle: "Repeat each sentence clearly",
        durationLabel: "5 min",
        iconName: "text.bubble",
        category: "fluency",
        isActive: true,
        displayOrder: 1,
        createdAt: Date(),
        items: stubItems
    )

    let vm = ExerciseSessionViewModel(exercise: stubExercise)

    return NavigationStack {
        ExerciseSessionView(viewModel: vm) { state in
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if let item = state.currentItem {
                    Text(item.prompt)
                        .brandStyle(.body)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Loading prompt…")
                        .brandStyle(.callout)
                }
            }
        }
    }
}
