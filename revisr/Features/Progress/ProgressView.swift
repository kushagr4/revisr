import SwiftData
import SwiftUI

private enum ProgressDestination: Identifiable {
    case editor(StudyResultKind, StudyResult?)
    case history(StudyResultKind)

    var id: String {
        switch self {
        case .editor(let kind, let result): "editor-\(kind.rawValue)-\(result?.id.uuidString ?? "new")"
        case .history(let kind): "history-\(kind.rawValue)"
        }
    }
}

struct ProgressDashboardView: View {
    @EnvironmentObject private var presentation: AppPresentationState
    @State private var range: ProgressRange = .thisWeek
    @State private var destination: ProgressDestination?

    var body: some View {
        ProgressRangeContent(
            range: range,
            onEditResult: { kind, result in destination = .editor(kind, result) },
            onViewHistory: { kind in destination = .history(kind) }
        )
        .id(range)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    presentation.presentQuickStudyEntry()
                } label: {
                    Label("Log Study", systemImage: "stopwatch")
                }
                .accessibilityHint("Opens the quick study entry form")

                Menu {
                    Button("TMUA Result", systemImage: "doc.text") {
                        destination = .editor(.tmua, nil)
                    }
                    Button("A-Level Result", systemImage: "function") {
                        destination = .editor(.aLevel, nil)
                    }
                } label: {
                    Label("Add Result", systemImage: "plus")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: RevisrSpacing.xSmall) {
                Picker("Progress range", selection: $range) {
                    ForEach(ProgressRange.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("progress-range-picker")

                Text(range.subtitle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, RevisrSpacing.standard)
            .padding(.top, RevisrSpacing.small)
            .padding(.bottom, RevisrSpacing.compact)
            .background(.bar)
        }
        .sheet(item: $destination) { destination in
            switch destination {
            case .editor(let kind, let result):
                StudyResultEditorView(kind: kind, result: result)
            case .history(let kind):
                ResultsHistoryView(kind: kind)
            }
        }
        .tint(RevisrColors.accentTeal)
        .onAppear {
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--progress-add-tmua") {
                destination = .editor(.tmua, nil)
            } else if arguments.contains("--progress-add-alevel") {
                destination = .editor(.aLevel, nil)
            }
#endif
        }
    }
}

private struct ProgressRangeContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var sessions: [StudySession]
    @Query private var blocks: [PlannedStudyBlock]
    @Query private var results: [StudyResult]
    @Query private var settings: [AppSettings]

    let range: ProgressRange
    let onEditResult: (StudyResultKind, StudyResult?) -> Void
    let onViewHistory: (StudyResultKind) -> Void

    init(
        range: ProgressRange,
        onEditResult: @escaping (StudyResultKind, StudyResult?) -> Void,
        onViewHistory: @escaping (StudyResultKind) -> Void
    ) {
        self.range = range
        self.onEditResult = onEditResult
        self.onViewHistory = onViewHistory
        let interval = range.interval()
        let start = interval.start
        let end = interval.end
        _sessions = Query(
            filter: #Predicate<StudySession> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\StudySession.date, order: .reverse)]
        )
        _blocks = Query(
            filter: #Predicate<PlannedStudyBlock> { $0.day >= start && $0.day < end },
            sort: [SortDescriptor(\PlannedStudyBlock.day, order: .reverse)]
        )
        _results = Query(
            filter: #Predicate<StudyResult> { $0.date >= start && $0.date < end },
            sort: [SortDescriptor(\StudyResult.date, order: .reverse)]
        )
        _settings = Query()
    }

    private var actualDuration: TimeInterval {
        sessions.reduce(0) { $0 + max(0, $1.duration) }
    }

    private var plannedDuration: TimeInterval {
        blocks.reduce(0) { $0 + max(0, $1.duration) }
    }

    private var allocations: [StudyAllocation] {
        ProgressAnalytics.allocations(sessions: sessions, settings: settings.first)
    }

    private var tmuaResults: [StudyResult] {
        ProgressAnalytics.tmuaResults(from: results)
    }

    private var aLevelResults: [StudyResult] {
        ProgressAnalytics.aLevelResults(from: results)
    }

    var body: some View {
        List {
            Section {
                StudyProgressSummary(
                    actualDuration: actualDuration,
                    plannedDuration: plannedDuration
                )
            }

            Section("Study allocation") {
                if actualDuration == 0 {
                    ProgressEmptyRow(
                        title: "No study logged",
                        message: "Log a study session to see how your time compares with your targets.",
                        systemImage: "clock"
                    )
                } else {
                    ForEach(allocations) { allocation in
                        AllocationRow(allocation: allocation)
                    }
                }
            }

            ResultProgressSection(
                kind: .tmua,
                results: tmuaResults,
                onAdd: { onEditResult(.tmua, nil) },
                onEdit: { onEditResult(.tmua, $0) },
                onViewHistory: { onViewHistory(.tmua) }
            )

            ResultProgressSection(
                kind: .aLevel,
                results: aLevelResults,
                onAdd: { onEditResult(.aLevel, nil) },
                onEdit: { onEditResult(.aLevel, $0) },
                onViewHistory: { onViewHistory(.aLevel) }
            )
        }
        .listStyle(.insetGrouped)
        .animation(reduceMotion ? nil : .default, value: results.count)
    }
}

private struct StudyProgressSummary: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let actualDuration: TimeInterval
    let plannedDuration: TimeInterval

    private var progress: Double {
        StudyAnalytics.completionFraction(planned: plannedDuration, actual: actualDuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.compact) {
            Text("STUDY TIME")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(DateUtilities.durationText(actualDuration))
                .font(RevisrTypography.metric)
                .monospacedDigit()
                .accessibilityAddTraits(.isHeader)

            if plannedDuration > 0 {
                if dynamicTypeSize.isAccessibilitySize {
                    plannedSummary
                } else {
                    HStack(spacing: RevisrSpacing.compact) {
                        SwiftUI.ProgressView(value: progress)
                            .tint(RevisrColors.accentTeal)
                        plannedSummary
                    }
                }
            } else {
                Text(actualDuration > 0 ? "No study was planned in this range." : "No study logged in this range yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, RevisrSpacing.small)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var plannedSummary: some View {
        Text("of \(DateUtilities.durationText(plannedDuration)) planned")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var accessibilitySummary: String {
        if plannedDuration > 0 {
            return "\(DateUtilities.durationText(actualDuration)) studied of \(DateUtilities.durationText(plannedDuration)) planned."
        }
        return "\(DateUtilities.durationText(actualDuration)) studied. Nothing planned."
    }
}

private struct AllocationRow: View {
    let allocation: StudyAllocation

    private var percentageText: String {
        allocation.fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private var targetText: String {
        allocation.targetFraction.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            title
            detail
            SwiftUI.ProgressView(value: allocation.fraction)
                .tint(RevisrColors.subjectAccent(allocation.category.accentIdentifier))
        }
        .padding(.vertical, RevisrSpacing.xSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(allocation.category.title), \(DateUtilities.durationText(allocation.duration)), \(percentageText) of study time, target \(targetText).")
    }

    private var title: some View {
        Label {
            Text(allocation.category.title)
                .font(.body.weight(.medium))
        } icon: {
            Circle()
                .fill(RevisrColors.subjectAccent(allocation.category.accentIdentifier))
                .frame(width: 9, height: 9)
        }
    }

    private var detail: some View {
        Text("\(DateUtilities.durationText(allocation.duration)) · \(percentageText) · target \(targetText)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }
}

struct ProgressEmptyRow: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: RevisrSpacing.compact) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(RevisrColors.accentTeal)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                Text(title).font(.body.weight(.medium))
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, RevisrSpacing.small)
        .accessibilityElement(children: .combine)
    }
}
