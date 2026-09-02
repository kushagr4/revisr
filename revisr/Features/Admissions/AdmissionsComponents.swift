import SwiftUI

struct AdmissionsStatusBadge: View {
    let text: String
    let systemImage: String
    var tint: Color = RevisrColors.accentTeal

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct AdmissionsMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .contentTransition(.numericText())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RevisrSpacing.standard)
        .background(RevisrColors.secondaryBackground, in: RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
        .accessibilityElement(children: .combine)
    }
}

struct AdmissionsQuestionRow: View {
    let question: AdmissionsQuestion
    var assignment: ProgrammeAssignment?
    var solutionLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(question.externalQuestionID)
                    .font(.headline)
                Spacer()
                Text("D\(question.difficulty)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Difficulty \(question.difficulty), \(question.difficultyLabel)")
            }
            Text(sourceLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(question.primaryTopic)
                .font(.subheadline)
            if let assignment {
                Text([assignment.block, assignment.purpose].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: RevisrSpacing.small) {
                if let cap = assignment?.suggestedTimeCapMinutes {
                    Label("\(cap) min", systemImage: "timer")
                }
                if let latest = question.latestAttempt {
                    Label(latest.outcome.title, systemImage: latest.outcome.systemImage)
                } else {
                    Label("Unattempted", systemImage: "circle.dashed")
                }
                if question.reviewState != .none {
                    Label(question.reviewState.title, systemImage: "bookmark.fill")
                }
                if let solutionLabel {
                    Label(solutionLabel, systemImage: "checkmark.seal")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var sourceLine: String {
        let source = question.sourceDocument?.displayName ?? question.family
        let paper = question.paper.map { " · \($0)" } ?? ""
        return "\(source)\(paper) · Question \(question.questionLabel)"
    }

    private var accessibilitySummary: String {
        let latest = question.latestAttempt?.outcome.title ?? "Unattempted"
        let review = question.reviewState == .none ? "" : ", \(question.reviewState.title)"
        let solution = solutionLabel.map { ", \($0)" } ?? ""
        return "\(question.externalQuestionID), \(sourceLine), \(question.primaryTopic), difficulty \(question.difficulty), \(latest)\(review)\(solution)"
    }
}

extension Duration {
    static func admissionsMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }
}
