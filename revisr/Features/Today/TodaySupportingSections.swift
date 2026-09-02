import SwiftUI

struct AdditionalStudyView: View {
    let sessions: [StudySession]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                HStack(alignment: .firstTextBaseline, spacing: RevisrSpacing.compact) {
                    VStack(alignment: .leading, spacing: RevisrSpacing.xSmall) {
                        Text(session.subjectNameSnapshot)
                            .font(.body.weight(.medium))
                        Text([session.moduleNameSnapshot, session.topicNameSnapshot, session.activity.title]
                            .compactMap { $0 }
                            .joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(DateUtilities.durationText(session.duration))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, RevisrSpacing.small)
                .accessibilityElement(children: .combine)

                if index < sessions.count - 1 {
                    Divider()
                }
            }
        }
    }
}

struct WeeklyFocusView: View {
    let items: [WeeklyFocus]

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: RevisrSpacing.compact) {
                    Circle()
                        .fill(RevisrColors.accentTeal)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                    Text(item.title)
                        .font(.body)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, RevisrSpacing.xSmall)
    }
}

struct ExamCountdownView: View {
    let examDate: Date
    let today: Date
    let calendar: Calendar

    private var daysRemaining: Int {
        DateUtilities.daysUntil(examDate, from: today, calendar: calendar)
    }

    var body: some View {
        HStack(spacing: RevisrSpacing.small) {
            Image(systemName: daysRemaining >= 0 ? "calendar.badge.clock" : "calendar")
                .foregroundStyle(RevisrColors.accentTeal)

            if daysRemaining > 1 {
                Text("TMUA · \(daysRemaining) days")
            } else if daysRemaining == 1 {
                Text("TMUA · Tomorrow")
            } else if daysRemaining == 0 {
                Text("TMUA · Today")
            } else {
                Text("TMUA exam date passed")
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

struct TodayEmptyStateView: View {
    let isAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            Label(
                isAvailable ? "Nothing planned today" : "No study planned",
                systemImage: isAvailable ? "calendar.badge.plus" : "moon.zzz"
            )
            .font(.headline)

            Text(
                isAvailable
                    ? "Add a study block in Plan or log study with +."
                    : "Today is marked unavailable. You can still log study with +."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, RevisrSpacing.small)
        .accessibilityElement(children: .combine)
    }
}
