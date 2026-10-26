import SwiftData
import SwiftUI

struct TMUAResultsView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    let snapshot: TMUADiagnosticSnapshot
    @State private var showingExpansion = false
    @State private var errorMessage: String?
    @Query private var programmes: [PublicProgramme]

    private var content: TMUAContentContext? { TMUAContentStore.context() }

    private var hasProgramme: Bool {
        programmes.contains { $0.stableID == TMUAProgrammeService.programmeID(settings: settings) }
    }

    var body: some View {
        if let syllabus = content?.syllabus {
            let report = TMUADiagnosticReportBuilder.build(snapshot: snapshot, syllabus: syllabus)
            List {
                scoreSection(report)
                confidenceSection(report)
                topicSections(report, syllabus: syllabus)
                if !report.skills.isEmpty {
                    Section("Paper 2 reasoning skills") {
                        ForEach(report.skills, id: \.name) { TMUAEvidenceRow(result: $0) }
                    }
                }
                questionReview(syllabus: syllabus)
                nextSteps(report)
            }
            .navigationTitle("Diagnostic results")
            .sheet(isPresented: $showingExpansion) {
                TMUAExpansionView(settings: settings, snapshot: snapshot)
            }
            .alert("Couldn’t Build Plan", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        } else {
            ContentUnavailableView("Results unavailable", systemImage: "exclamationmark.triangle",
                description: Text("The syllabus could not be loaded. Your submitted answers are saved."))
        }
    }

    private func scoreSection(_ report: TMUADiagnosticReport) -> some View {
        Section {
            VStack(alignment: .leading, spacing: RevisrSpacing.compact) {
                Text("Raw score").font(RevisrTypography.label).foregroundStyle(RevisrColors.secondaryLabel)
                Text(report.combinedScore).font(.system(size: 44, weight: .bold, design: .rounded))
                    .accessibilityLabel("\(report.correct) correct out of \(report.questionCount)")
                HStack(spacing: RevisrSpacing.large) {
                    ForEach(report.papers, id: \.paper) { paper in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paper.paper.title).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                            Text(paper.rawScore).font(.title3.bold().monospacedDigit())
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: RevisrSpacing.large, verticalSpacing: 4) {
                    GridRow { Text("Answered"); Text("\(report.answered)").monospacedDigit() }
                    GridRow { Text("Skipped"); Text("\(report.skipped)").monospacedDigit() }
                    GridRow { Text("Active time"); Text(TMUAAssessmentView.clock(Double(report.activeSeconds))).monospacedDigit() }
                    GridRow { Text("Topics sampled"); Text("\(report.sampledTopicKeys.count) of \(report.sampledTopicKeys.count + report.unassessedTopicKeys.count)").monospacedDigit() }
                }
                .font(.subheadline)
                Text(report.scoreDisclaimer).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
            }
            .padding(.vertical, RevisrSpacing.small)
        }
    }

    private func confidenceSection(_ report: TMUADiagnosticReport) -> some View {
        Section("How much this tells us") {
            VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                RevisrStatusLabel(title: "\(report.length.title) diagnostic · \(report.length.confidenceTitle) evidence",
                                  systemImage: "gauge.with.dots.needle.33percent", color: RevisrColors.accentTeal)
                Text(report.length.confidenceExplanation).font(.subheadline)
                Text(report.timingNote).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                Text(report.compositionNote).font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
            }
            .padding(.vertical, RevisrSpacing.xSmall)
        }
    }

    @ViewBuilder
    private func topicSections(_ report: TMUADiagnosticReport, syllabus: TMUASyllabus) -> some View {
        let groups: [(DiagnosticEvidenceLevel, String)] = [
            (.strongDifficulty, "Stronger evidence of difficulty"),
            (.possibleImprovement, "Possible areas for improvement"),
            (.relativeStrength, "Relative strengths"),
            (.insufficient, "Sampled, but not enough evidence yet")
        ]
        ForEach(groups, id: \.1) { level, title in
            let rows = report.topics.filter { $0.level == level }
            if !rows.isEmpty {
                Section(title) { ForEach(rows, id: \.name) { TMUAEvidenceRow(result: $0) } }
            }
        }
        if !report.unassessedTopicKeys.isEmpty {
            Section {
                ForEach(report.unassessedTopicKeys, id: \.self) { key in
                    Text(syllabus.topicTitle(key))
                }
            } header: {
                Text("Not assessed in this diagnostic")
            } footer: {
                Text("No conclusion is drawn about these topics. Your plan still includes them as baseline revision.")
            }
        }
    }

    private func questionReview(syllabus: TMUASyllabus) -> some View {
        let submitted = Set(snapshot.sections.filter { $0.status == .submitted }.map(\.stableID))
        let sections = snapshot.sections.filter { submitted.contains($0.stableID) }
        return Section("Review your answers") {
            ForEach(sections, id: \.stableID) { section in
                ForEach(Array(snapshot.items(in: section).enumerated()), id: \.element.stableID) { offset, item in
                    NavigationLink {
                        TMUADiagnosticItemReview(item: item, number: offset + 1, paper: section.paper)
                    } label: {
                        HStack {
                            Image(systemName: item.marking == .correct ? "checkmark.circle.fill"
                                  : item.marking == .incorrect ? "xmark.circle.fill" : "minus.circle")
                                .foregroundStyle(item.marking == .correct ? RevisrColors.success
                                                 : item.marking == .incorrect ? RevisrColors.critical : RevisrColors.secondaryLabel)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(section.paper.title) · Q\(offset + 1)\(section.round > 0 ? " (added)" : "")")
                                    .font(.subheadline.weight(.semibold))
                                Text(syllabus.strandTitle(item.strandKey)).font(.caption)
                                    .foregroundStyle(RevisrColors.secondaryLabel)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(item.marking == .correct ? "Correct" : item.marking == .incorrect ? "Incorrect" : "Skipped")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func nextSteps(_ report: TMUADiagnosticReport) -> some View {
        Section {
            if !hasProgramme {
                Text(report.length == .comprehensive
                     ? "Your plan will prioritise the topics above where the evidence is clearer, while keeping every syllabus area in rotation."
                     : "Your plan will treat these findings as provisional: it leans gently towards the areas above and keeps broad syllabus coverage, including topics this diagnostic did not sample.")
                    .font(.subheadline)
                Button {
                    generate()
                } label: {
                    Label("Generate my personalised plan", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            if snapshot.openSections.isEmpty, !snapshot.diagnostic.targetLength.expansionTargets.isEmpty {
                Button("Improve my diagnostic accuracy") { showingExpansion = true }
                Text("Optional. Answer more questions to sample more of the syllabus; your earlier answers are kept.")
                    .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
            }
        }
    }

    private func generate() {
        guard let content else { return }
        do {
            try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct TMUAEvidenceRow: View {
    let result: DiagnosticTopicResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.name).font(.headline)
            let style = Self.style(result.level)
            RevisrStatusLabel(title: result.level.title, systemImage: style.0, color: style.1)
            Text(result.explanation).font(.subheadline).foregroundStyle(RevisrColors.secondaryLabel)
            if result.unansweredCount > 0 {
                Text("\(result.unansweredCount) skipped (not counted as incorrect)")
                    .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
            }
        }
        .padding(.vertical, RevisrSpacing.xSmall)
        .accessibilityElement(children: .combine)
    }

    static func style(_ level: DiagnosticEvidenceLevel) -> (String, Color) {
        switch level {
        case .strongDifficulty: ("exclamationmark.triangle.fill", RevisrColors.critical)
        case .possibleImprovement: ("arrow.up.right.circle.fill", RevisrColors.warning)
        case .relativeStrength: ("checkmark.circle.fill", RevisrColors.success)
        case .insufficient: ("questionmark.circle.fill", RevisrColors.secondaryLabel)
        }
    }
}

/// A submitted diagnostic question with the student's locked answer and the
/// worked solution. Only reachable after submission.
struct TMUADiagnosticItemReview: View {
    let item: TMUADiagnosticItem
    let number: Int
    let paper: TMUAPaper

    var body: some View {
        ScrollView {
            if let content = item.content, item.marking != nil {
                VStack(alignment: .leading, spacing: RevisrSpacing.large) {
                    Text(content.category.attributionTitle).font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    MathText(content.stem, textStyle: .title3)
                    VStack(spacing: RevisrSpacing.compact) {
                        ForEach(content.options, id: \.id) { option in
                            TMUAOptionButton(option: option, selected: item.selectedOptionID == option.id,
                                state: option.id == content.correctOptionId
                                    ? (item.selectedOptionID == option.id ? .correct : .key)
                                    : (item.selectedOptionID == option.id ? .incorrect : .neutral)) {}
                                .allowsHitTesting(false)
                        }
                    }
                    if item.selectedOptionID == nil {
                        Label("You skipped this question.", systemImage: "minus.circle")
                            .foregroundStyle(RevisrColors.secondaryLabel)
                    }
                    TMUASolutionCard(solution: content.solution)
                }
                .padding(RevisrSpacing.large)
            } else {
                ContentUnavailableView("Solution locked", systemImage: "lock",
                    description: Text("Worked solutions appear after the section is submitted."))
            }
        }
        .navigationTitle("\(paper.title) · Q\(number)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TMUASolutionCard: View {
    let solution: String

    var body: some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            Label("Worked solution", systemImage: "lightbulb").font(.headline)
            MathText(solution, textStyle: .body)
        }
        .padding(RevisrSpacing.standard)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RevisrColors.tintedSurface, in: RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
    }
}

// MARK: - Expansion

struct TMUAExpansionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let settings: AppSettings
    let snapshot: TMUADiagnosticSnapshot
    @State private var target: TMUADiagnosticLength?
    @State private var errorMessage: String?

    var body: some View {
        let current = snapshot.diagnostic.targetLength
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RevisrSpacing.large) {
                    VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                        Text("Improve my diagnostic accuracy").font(.title2.bold())
                        Text("You answered \(current.totalQuestions) questions. Adding more samples more of the syllabus and refines your future priorities. Your submitted answers, scores and completed revision stay exactly as they are.")
                            .foregroundStyle(RevisrColors.secondaryLabel)
                    }
                    ForEach(current.expansionTargets) { option in
                        let addOne = current.additionalQuestions(to: option, paper: .one)
                        let addTwo = current.additionalQuestions(to: option, paper: .two)
                        let available = TMUAContentStore.context().map {
                            TMUADiagnosticService.canExpand(snapshot, to: option, settings: settings,
                                                            content: $0, in: modelContext)
                        } ?? false
                        Button {
                            target = option
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(current.totalQuestions) → \(option.totalQuestions) questions").font(.headline)
                                    Spacer()
                                    Image(systemName: target == option ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(target == option ? RevisrColors.accentTeal : RevisrColors.secondaryLabel)
                                }
                                Text("Adds \(addOne) Paper 1 and \(addTwo) Paper 2 questions · \(option.title)")
                                    .font(.subheadline)
                                if !available {
                                    Text("Not enough unseen approved questions are available for this option.")
                                        .font(.footnote).foregroundStyle(RevisrColors.warning)
                                }
                            }
                            .padding(RevisrSpacing.standard)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RevisrColors.secondaryBackground,
                                        in: RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                        .opacity(available ? 1 : 0.6)
                        .accessibilityAddTraits(target == option ? .isSelected : [])
                    }
                    Text("Added questions are answered in new sections with their own timing. Questions you have already seen in the diagnostic or in practice are never reused as new evidence.")
                        .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                }
                .padding(RevisrSpacing.large)
            }
            .navigationTitle("Add questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add questions") { expand() }.disabled(target == nil)
                }
            }
            .alert("Couldn’t Add Questions", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func expand() {
        guard let target, let content = TMUAContentStore.context() else { return }
        do {
            _ = try TMUADiagnosticService.expand(snapshot, to: target, settings: settings,
                                                 content: content, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
