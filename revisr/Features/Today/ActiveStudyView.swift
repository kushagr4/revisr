import SwiftUI

struct ActiveStudyView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let state: StudyTimerState
    let onPause: () -> Void
    let onResume: () -> Void
    let onFinish: () -> Void

    private var title: String {
        [state.subject?.name, state.module?.name]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.compact) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                    statusLabel
                    timerText
                }
            } else {
                HStack {
                    statusLabel
                    Spacer()
                    timerText
                }
            }

            VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                Text(title.isEmpty ? "Study session" : title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(state.activity.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: RevisrSpacing.small) {
                    pauseResumeButton
                    finishButton
                }
            } else {
                HStack(spacing: RevisrSpacing.small) {
                    pauseResumeButton
                    finishButton
                }
            }
        }
        .padding(RevisrSpacing.standard)
        .background(RevisrColors.secondaryBackground, in: RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
        .accessibilityElement(children: .contain)
    }

    private var statusLabel: some View {
        Label(
            state.status == .paused ? "Paused" : "Studying now",
            systemImage: state.status == .paused ? "pause.fill" : "timer"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(RevisrColors.accentTeal)
    }

    private var timerText: some View {
        Text(
            timerInterval: timerStart...Date.distantFuture,
            pauseTime: state.status == .paused ? timerStart.addingTimeInterval(state.accumulatedDuration) : nil,
            countsDown: false,
            showsHours: state.elapsed() >= 3_600
        )
            .font(.title2.monospacedDigit().weight(.semibold))
    }

    private var timerStart: Date {
        if let runningSince = state.runningSince {
            return runningSince.addingTimeInterval(-state.accumulatedDuration)
        }
        return Date.now.addingTimeInterval(-state.accumulatedDuration)
    }

    private var pauseResumeButton: some View {
        Button(
            state.status == .paused ? "Resume" : "Pause",
            systemImage: state.status == .paused ? "play.fill" : "pause.fill",
            action: state.status == .paused ? onResume : onPause
        )
        .buttonStyle(.bordered)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
        .controlSize(.regular)
    }

    private var finishButton: some View {
        Button("Finish", systemImage: "checkmark", action: onFinish)
            .buttonStyle(.borderedProminent)
            .tint(RevisrColors.accentTeal)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            .controlSize(.regular)
    }
}
