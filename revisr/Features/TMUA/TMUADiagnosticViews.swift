import SwiftData
import SwiftUI

// MARK: - Hub

struct TMUADiagnosticHubView: View {
    @Environment(\.modelContext) private var modelContext
    let settings: AppSettings
    /// Embedded inside the main tabs after a plan exists.
    var embedded = false

    @Query private var allSections: [TMUADiagnosticSection]
    @Query private var allItems: [TMUADiagnosticItem]
    @State private var snapshot: TMUADiagnosticSnapshot?
    @State private var activeSection: TMUADiagnosticSection?
    @State private var showingLengthPicker = false
    @State private var showingExpansion = false
    @State private var pendingLength: TMUADiagnosticLength?
    @State private var errorMessage: String?
    @State private var isGenerating = false
    @State private var showingResults = false

    private var content: TMUAContentContext? { TMUAContentStore.context() }

    var body: some View {
        let wrapped = List {
            header
            if let snapshot {
                rounds(snapshot)
                if snapshot.isInitialComplete { completeSection(snapshot) }
            } else {
                unavailableSection
            }
            Section {
                if !embedded {
                    Button("Edit preparation details") {
                        settings.publicOnboardingStage = .profile
                    }
                }
            } footer: {
                Text("Answers save on this iPhone after every change. Revisr’s diagnostic is a preparation assessment, not an official TMUA paper.")
            }
        }
        .navigationTitle("Diagnostic")
        .onAppear(perform: refresh)
        .navigationDestination(isPresented: $showingResults) {
            if let snapshot { TMUAResultsView(settings: settings, snapshot: snapshot) }
        }
#if DEBUG
        .task {
            guard let open = DebugTMUAScenarioService.value("--tmua-open"), let snapshot else { return }
            if open == "results" { showingResults = snapshot.isInitialComplete }
            if open == "session" || open == "overview",
               let section = snapshot.sections.first(where: { $0.status == .inProgress }) {
                self.open(section)
            }
        }
#endif
        .onChange(of: allSections.map(\.statusRawValue)) { _, _ in refresh() }
        .fullScreenCover(item: $activeSection, onDismiss: refresh) { section in
            if let snapshot {
                TMUAAssessmentView(settings: settings, section: section, snapshot: snapshot)
            }
        }
        .sheet(isPresented: $showingLengthPicker) { lengthSheet }
        .sheet(isPresented: $showingExpansion, onDismiss: refresh) {
            if let snapshot {
                TMUAExpansionView(settings: settings, snapshot: snapshot)
            }
        }
        .alert("Couldn’t Continue", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }

        if embedded {
            wrapped
        } else {
            NavigationStack { wrapped }
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                Text(snapshot?.isInitialComplete == true ? "Diagnostic complete" : "Find your starting point")
                    .font(RevisrTypography.cardTitle)
                if let snapshot {
                    let length = snapshot.diagnostic.targetLength
                    Text("\(length.title) · \(length.totalQuestions) questions · Paper 1: \(length.paperOneQuestions), Paper 2: \(length.paperTwoQuestions)")
                        .font(.subheadline.weight(.medium))
                    Text(snapshot.diagnostic.sourceCompositionNote)
                        .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
                    let answered = snapshot.items.filter { $0.selectedOptionID != nil }.count
                    ProgressView(value: Double(answered), total: Double(max(1, snapshot.items.count))) {
                        Text("\(answered) of \(snapshot.items.count) answered")
                            .font(.caption).foregroundStyle(RevisrColors.secondaryLabel)
                    }
                    .tint(RevisrColors.accentTeal)
                    .accessibilityRepresentation { Text("\(answered) of \(snapshot.items.count) answered") }
                } else {
                    Text("Answer a mixture of TMUA-style questions so Revisr can shape your plan.")
                        .foregroundStyle(RevisrColors.secondaryLabel)
                }
                if content?.distribution == .internal {
                    RevisrStatusLabel(title: "Development content · not yet reviewed",
                                      systemImage: "hammer", color: RevisrColors.warning)
                }
            }
            .padding(.vertical, RevisrSpacing.small)
        }
    }

    @ViewBuilder
    private func rounds(_ snapshot: TMUADiagnosticSnapshot) -> some View {
        let grouped = Dictionary(grouping: snapshot.sections, by: \.round)
        ForEach(grouped.keys.sorted(), id: \.self) { round in
            let sections = (grouped[round] ?? []).sorted { $0.paperRawValue < $1.paperRawValue }
            Section {
                ForEach(sections, id: \.stableID) { section in
                    sectionRow(section, snapshot: snapshot, locked: isLocked(section, in: sections))
                }
                if round == 0 && sections.allSatisfy({ $0.status == .notStarted })
                    && snapshot.items.allSatisfy({ $0.selectedOptionID == nil }) {
                    Button("Change diagnostic length") {
                        pendingLength = snapshot.diagnostic.targetLength
                        showingLengthPicker = true
                    }
                }
            } header: {
                Text(round == 0 ? "Diagnostic" : "Added questions · round \(round + 1)")
            } footer: {
                if round > 0 {
                    Text("These questions extend your earlier diagnostic. Earlier answers stay exactly as you submitted them.")
                }
            }
        }
    }

    private func isLocked(_ section: TMUADiagnosticSection, in round: [TMUADiagnosticSection]) -> Bool {
        section.paper == .two && round.first(where: { $0.paper == .one })?.status != .submitted
    }

    private func sectionRow(_ section: TMUADiagnosticSection, snapshot: TMUADiagnosticSnapshot,
                            locked: Bool) -> some View {
        let items = snapshot.items(in: section)
        let answered = items.filter { $0.selectedOptionID != nil }.count
        return VStack(alignment: .leading, spacing: RevisrSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.paper.title).font(.headline)
                    Text(section.paper.subtitle).font(.subheadline).foregroundStyle(RevisrColors.secondaryLabel)
                }
                Spacer()
                statusBadge(section, locked: locked)
            }
            Text("\(items.count) questions · suggested \(section.advisoryMinutes) minutes\(section.roundTargetLength.isFullLengthSections && section.round == 0 ? "" : " · abbreviated section")")
                .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
            switch section.status {
            case .notStarted:
                Button(locked ? "Submit Paper 1 to unlock" : "Start \(section.paper.title)") { open(section) }
                    .buttonStyle(.borderedProminent).tint(RevisrColors.accentFill)
                    .disabled(locked)
                    .accessibilityIdentifier("hub.start.\(rowKey(section))")
            case .inProgress:
                Text("\(answered) of \(items.count) answered · saved").font(.subheadline)
                    .accessibilityIdentifier("hub.progress.\(rowKey(section))")
                Button("Resume at question \(section.currentIndex + 1)") { open(section) }
                    .buttonStyle(.borderedProminent).tint(RevisrColors.accentFill)
                    .accessibilityIdentifier("hub.resume.\(rowKey(section))")
            case .submitted:
                let correct = items.filter { $0.marking == .correct }.count
                Text("Submitted · \(correct) / \(items.count) correct").font(.subheadline)
                    .accessibilityIdentifier("hub.submitted.\(rowKey(section))")
            }
        }
        .padding(.vertical, RevisrSpacing.xSmall)
    }

    private func rowKey(_ section: TMUADiagnosticSection) -> String {
        "R\(section.round).P\(section.paperRawValue)"
    }

    private func statusBadge(_ section: TMUADiagnosticSection, locked: Bool) -> some View {
        let (title, symbol, color): (String, String, Color) = switch section.status {
        case .notStarted: locked ? ("Locked", "lock.fill", RevisrColors.secondaryLabel)
            : ("Ready", "circle", RevisrColors.accentStrong)
        case .inProgress: ("Paused", "pause.circle.fill", RevisrColors.warning)
        case .submitted: ("Submitted", "checkmark.circle.fill", RevisrColors.success)
        }
        return RevisrStatusLabel(title: title, systemImage: symbol, color: color)
    }

    @ViewBuilder
    private func completeSection(_ snapshot: TMUADiagnosticSnapshot) -> some View {
        Section("Results") {
            NavigationLink {
                TMUAResultsView(settings: settings, snapshot: snapshot)
            } label: {
                Label("View your diagnostic results", systemImage: "chart.bar.doc.horizontal")
            }
            .accessibilityIdentifier("hub.results")
            if !embedded {
                Button {
                    generatePlan()
                } label: {
                    Label(isGenerating ? "Building your plan…" : "Generate my personalised plan",
                          systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(RevisrColors.accentFill)
                .disabled(isGenerating)
                .accessibilityIdentifier("hub.generatePlan")
            }
            if snapshot.openSections.isEmpty, !snapshot.diagnostic.targetLength.expansionTargets.isEmpty {
                Button("Improve my diagnostic accuracy") { showingExpansion = true }
                    .accessibilityIdentifier("hub.improve")
            }
        }
    }

    @ViewBuilder
    private var unavailableSection: some View {
        let length = settings.publicDiagnosticLength ?? .starter
        Section("Content availability") {
            Label(content?.availability(for: length).message
                  ?? "Question content could not be loaded in this build.",
                  systemImage: "exclamationmark.triangle")
                .foregroundStyle(RevisrColors.secondaryLabel)
                .accessibilityIdentifier("hub.unavailable")
            Text("Your examination date and study availability are saved.")
                .font(.footnote).foregroundStyle(RevisrColors.secondaryLabel)
            if let content, TMUADiagnosticLength.allCases.contains(where: { content.availability(for: $0).isAvailable }) {
                Button("Choose a different length") {
                    pendingLength = length
                    showingLengthPicker = true
                }
            }
        }
        // Without a diagnostic there is no plan and no tabs, so the library would otherwise be
        // out of reach in a build with no approved questions.
        Section {
            NavigationLink {
                List { TMUAResourceLibraryView(settings: settings, content: content) }
                    .navigationTitle("Papers & sources")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                Label("Browse papers and sources", systemImage: "books.vertical")
            }
            .accessibilityIdentifier("hub.library")
        } footer: {
            Text("Official papers and other sources open on their publishers’ websites. Results you record yourself track your progress but are not used as evidence of topic mastery.")
        }
    }

    private var lengthSheet: some View {
        NavigationStack {
            ScrollView {
                TMUALengthPicker(selection: $pendingLength).padding(RevisrSpacing.large)
            }
            .navigationTitle("Diagnostic length")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingLengthPicker = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { applyLength() }.disabled(pendingLength == nil)
                }
            }
        }
    }

    private func applyLength() {
        guard let length = pendingLength, let content else { return }
        do {
            if let snapshot {
                self.snapshot = try TMUADiagnosticService.changeLength(snapshot, to: length,
                    settings: settings, content: content, in: modelContext)
            } else {
                self.snapshot = try TMUADiagnosticService.create(settings: settings, length: length,
                    content: content, in: modelContext)
            }
            showingLengthPicker = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ section: TMUADiagnosticSection) {
        guard let snapshot else { return }
        do {
            if section.status == .notStarted {
                try TMUADiagnosticService.start(section, in: snapshot, in: modelContext)
            } else {
                try TMUADiagnosticService.resume(section, in: modelContext)
            }
            activeSection = section
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refresh() {
        do {
            guard let loaded = try TMUADiagnosticService.load(settings: settings, in: modelContext) else {
                snapshot = nil
                return
            }
            if activeSection == nil { try TMUADiagnosticService.recoverInterruptedTimers(loaded, in: modelContext) }
            snapshot = loaded
            if loaded.isInitialComplete, settings.publicOnboardingStage == .diagnostics {
                settings.publicOnboardingStage = .diagnosticsComplete
                try modelContext.save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generatePlan() {
        guard let content else { return }
        isGenerating = true
        defer { isGenerating = false }
        do {
            try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, resourceSessions: true, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Assessment session

struct TMUAAssessmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let settings: AppSettings
    let section: TMUADiagnosticSection
    let snapshot: TMUADiagnosticSnapshot

    @State private var showingOverview = Self.debugOverview
    @State private var showingSubmit = false
    @State private var paused = false
    @State private var pausedInBackground = false
    @State private var errorMessage: String?
    @State private var savedPulse = false

    private var items: [TMUADiagnosticItem] { snapshot.items(in: section) }
    private var index: Int { min(section.currentIndex, max(0, items.count - 1)) }
    private var item: TMUADiagnosticItem? { items.indices.contains(index) ? items[index] : nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressHeader
                ScrollView {
                    if let item, let content = item.content {
                        questionBody(item, content: content)
                            .padding(RevisrSpacing.large)
                            .frame(maxWidth: 700)
                            .frame(maxWidth: .infinity)
                            .id(item.stableID)
                    } else {
                        ContentUnavailableView("Question unavailable", systemImage: "exclamationmark.triangle",
                            description: Text("This saved question could not be displayed. Your other answers are unaffected."))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle(section.paper.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Pause", systemImage: "pause.circle") { pause() }
                        .accessibilityHint("Stops the timer. Your answers stay saved.")
                        .accessibilityIdentifier("assessment.pause")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Overview", systemImage: "square.grid.3x3") { showingOverview = true }
                        .accessibilityIdentifier("assessment.overview")
                }
            }
            .overlay { if paused { pausedOverlay } }
            .sheet(isPresented: $showingOverview) { overview }
            .sheet(isPresented: $showingSubmit) { submitSheet }
            .onChange(of: scenePhase) { _, phase in
                // Leaving the app (Home, lock, app switcher, a call) stops the
                // clock; the student resumes explicitly when they return.
                guard phase != .active, section.status == .inProgress, !paused else { return }
                pauseTimer()
                pausedInBackground = true
                paused = true
            }
            .onDisappear(perform: pauseTimer)
            .task(id: paused) { await checkpointWhileRunning() }
            .alert("Couldn’t Save", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .interactiveDismissDisabled()
    }

    /// Compact progress chrome. Its text size is capped so that, at the largest sizes, the
    /// question rather than the header fills the screen; the question text is never capped.
    private var progressHeader: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: RevisrSpacing.small) {
                Text("Question \(index + 1) of \(items.count)").font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("assessment.position")
                Spacer(minLength: RevisrSpacing.small)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let clock = Self.clock(section.elapsed(at: context.date))
                    Label(clock, systemImage: "clock")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(RevisrColors.secondaryLabel)
                        .accessibilityLabel("Active time")
                        .accessibilityValue(clock)
                        .accessibilityIdentifier("assessment.timer")
                }
                Label(savedPulse ? "Saved" : "Saved", systemImage: "checkmark.icloud")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(RevisrColors.success)
                    .accessibilityLabel("Answers saved on this iPhone")
                    .accessibilityIdentifier("assessment.saved")
            }
            ProgressView(value: Double(items.filter { $0.selectedOptionID != nil }.count),
                         total: Double(max(1, items.count)))
                .tint(RevisrColors.accentTeal)
                .accessibilityRepresentation {
                    Text("\(items.filter { $0.selectedOptionID != nil }.count) of \(items.count) answered")
                }
                .accessibilityIdentifier("assessment.progress")
            if !dynamicTypeSize.isAccessibilitySize {
                Text("Suggested time \(section.advisoryMinutes) minutes · nothing is submitted automatically")
                    .font(.caption2).foregroundStyle(RevisrColors.secondaryLabel)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, RevisrSpacing.large)
        .padding(.vertical, RevisrSpacing.small)
        .background(.bar)
    }

    private func questionBody(_ item: TMUADiagnosticItem, content: TMUAContentItem) -> some View {
        VStack(alignment: .leading, spacing: RevisrSpacing.standard) {
            if item.isFlagged {
                Label("Flagged", systemImage: "flag.fill").font(.caption.weight(.semibold))
                    .foregroundStyle(RevisrColors.warning)
                    .accessibilityIdentifier("assessment.flagged")
            }
            TMUAQuestionStem(content: content)
                .padding(.horizontal, content.presentation == nil ? 0 : -(RevisrSpacing.large - 6))
            TMUAAnswerOptions(content: content, selectedID: item.selectedOptionID) { option in
                choose(option.id == item.selectedOptionID ? nil : option.id, item: item)
            }
            TMUASourceCredit(content: content)
        }
    }

    private var controls: some View {
        HStack(spacing: RevisrSpacing.compact) {
            Button {
                move(to: index - 1)
            } label: {
                Label("Previous", systemImage: "chevron.left").labelStyle(.iconOnly)
                    .frame(minWidth: RevisrMetrics.minimumTapTarget, minHeight: RevisrMetrics.minimumTapTarget)
            }
            .buttonStyle(TMUABorderedControlStyle())
            .disabled(index == 0)
            .accessibilityLabel("Previous question")
            .accessibilityIdentifier("assessment.previous")

            Button {
                if let item { flag(!item.isFlagged, item: item) }
            } label: {
                Label(item?.isFlagged == true ? "Unflag" : "Flag",
                      systemImage: item?.isFlagged == true ? "flag.slash" : "flag")
                    .labelStyle(AdaptiveLabelStyle(iconOnly: dynamicTypeSize.isAccessibilitySize))
                    .frame(minWidth: RevisrMetrics.minimumTapTarget, minHeight: RevisrMetrics.minimumTapTarget)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("assessment.flag")

            Spacer()

            if index + 1 < items.count {
                Button {
                    move(to: index + 1)
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(AdaptiveLabelStyle(iconOnly: dynamicTypeSize.isAccessibilitySize))
                        .frame(minWidth: 88, minHeight: RevisrMetrics.minimumTapTarget)
                }
                .buttonStyle(.borderedProminent).tint(RevisrColors.accentFill)
                .accessibilityIdentifier("assessment.next")
            } else {
                Button { showingSubmit = true } label: {
                    ViewThatFits(in: .horizontal) {
                        Text("Review and submit")
                        Text("Review")
                    }
                    .lineLimit(1)
                    .frame(minHeight: RevisrMetrics.minimumTapTarget)
                }
                .buttonStyle(.borderedProminent).tint(RevisrColors.accentFill)
                .accessibilityLabel("Review and submit")
                .accessibilityIdentifier("assessment.review")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, RevisrSpacing.large)
        .padding(.vertical, RevisrSpacing.compact)
        .background(.bar)
    }

    private var overview: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: RevisrSpacing.large) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: RevisrSpacing.small)],
                              spacing: RevisrSpacing.small) {
                        ForEach(Array(items.enumerated()), id: \.element.stableID) { offset, row in
                            Button {
                                move(to: offset)
                                showingOverview = false
                            } label: {
                                overviewCell(offset: offset, item: row)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("overview.cell.\(offset + 1)")
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        legend("circle.fill", RevisrColors.accentTeal, "Answered")
                        legend("circle", RevisrColors.secondaryLabel, "Unanswered")
                        legend("flag.fill", RevisrColors.warning, "Flagged for review")
                        legend("square", RevisrColors.primaryLabel, "Current question (outlined)")
                    }
                    .font(.footnote)
                    Button("Review and submit") {
                        showingOverview = false
                        showingSubmit = true
                    }
                    .buttonStyle(.borderedProminent).tint(RevisrColors.accentFill)
                    .frame(maxWidth: .infinity)
                }
                .padding(RevisrSpacing.large)
            }
            .navigationTitle("Question overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingOverview = false }.accessibilityIdentifier("overview.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func overviewCell(offset: Int, item: TMUADiagnosticItem) -> some View {
        let answered = item.selectedOptionID != nil
        return ZStack(alignment: .topTrailing) {
            Text("\(offset + 1)")
                .font(.headline.monospacedDigit())
                .frame(width: 52, height: 52)
                .foregroundStyle(answered ? Color.white : RevisrColors.primaryLabel)
                .background(answered ? RevisrColors.accentFill : RevisrColors.secondaryBackground,
                            in: RoundedRectangle(cornerRadius: RevisrMetrics.compactCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: RevisrMetrics.compactCornerRadius)
                        .strokeBorder(offset == index ? RevisrColors.primaryLabel : .clear, lineWidth: 2)
                }
            if item.isFlagged {
                Image(systemName: "flag.fill").font(.caption2).foregroundStyle(RevisrColors.warning).padding(4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question \(offset + 1)")
        .accessibilityValue([answered ? "answered" : "unanswered", item.isFlagged ? "flagged" : nil,
                             offset == index ? "current" : nil].compactMap { $0 }.joined(separator: ", "))
    }

    private func legend(_ symbol: String, _ color: Color, _ title: String) -> some View {
        Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(color) }
    }

    private var submitSheet: some View {
        let answered = items.filter { $0.selectedOptionID != nil }.count
        let flagged = items.filter(\.isFlagged).count
        return NavigationStack {
            VStack(alignment: .leading, spacing: RevisrSpacing.large) {
                Text("Submit \(section.paper.title)?").font(.title2.bold())
                VStack(alignment: .leading, spacing: RevisrSpacing.small) {
                    LabeledContent("Answered", value: "\(answered)").accessibilityIdentifier("submit.answered")
                    LabeledContent("Unanswered", value: "\(items.count - answered)")
                        .accessibilityIdentifier("submit.unanswered")
                    LabeledContent("Flagged", value: "\(flagged)").accessibilityIdentifier("submit.flagged")
                }
                .font(.body.monospacedDigit())
                Text("Submitted answers are locked and marked. Unanswered questions score zero; there is no negative marking. Worked solutions become available after you submit.")
                    .foregroundStyle(RevisrColors.secondaryLabel)
                Spacer()
                Button {
                    submit()
                } label: {
                    Text("Submit and lock answers").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(RevisrColors.accentFill)
                .controlSize(.large)
                .accessibilityIdentifier("submit.confirm")
                Button("Keep working") { showingSubmit = false }
                    .accessibilityIdentifier("submit.keepWorking")
                    .frame(maxWidth: .infinity)
            }
            .padding(RevisrSpacing.large)
        }
        .presentationDetents([.medium, .large])
    }

    private var pausedOverlay: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: RevisrSpacing.large) {
                Image(systemName: "pause.circle.fill").font(.system(size: 56))
                    .foregroundStyle(RevisrColors.accentTeal).accessibilityHidden(true)
                Text("Paused").font(.title.bold()).accessibilityIdentifier("paused.title")
                Text((pausedInBackground ? "Revisr paused your timer while you were away. " : "")
                     + "The timer has stopped and your answers are saved. You can come back now or later, even after closing Revisr.")
                    .multilineTextAlignment(.center).foregroundStyle(RevisrColors.secondaryLabel)
                Button("Resume") { resume() }.buttonStyle(.borderedProminent).tint(RevisrColors.accentFill).controlSize(.large)
                    .accessibilityIdentifier("paused.resume")
                Button("Save and exit") {
                    paused = false
                    dismiss()
                }
                .accessibilityIdentifier("paused.exit")
            }
            .padding(RevisrSpacing.xLarge)
        }
    }

    // MARK: Actions

    private func choose(_ option: String?, item: TMUADiagnosticItem) {
        act { try TMUADiagnosticService.select(option, for: item, in: section, in: modelContext) }
    }

    private func flag(_ flagged: Bool, item: TMUADiagnosticItem) {
        act { try TMUADiagnosticService.setFlag(flagged, for: item, in: section, in: modelContext) }
    }

    private func move(to newIndex: Int) {
        act { try TMUADiagnosticService.move(section, to: newIndex, count: items.count, in: modelContext) }
    }

    private func pause() {
        pauseTimer()
        paused = true
    }

    private func pauseTimer() {
        guard section.status == .inProgress, section.runningSince != nil else { return }
        act { try TMUADiagnosticService.pause(section, in: modelContext) }
    }

    private func resume() {
        act { try TMUADiagnosticService.resume(section, in: modelContext) }
        paused = false
        pausedInBackground = false
    }

    /// Saves a lightweight checkpoint while the clock runs, so an abnormal
    /// termination loses at most one interval of active time.
    private func checkpointWhileRunning() async {
        guard !paused else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(TMUADiagnosticService.checkpointInterval))
            guard !Task.isCancelled, scenePhase == .active else { continue }
            try? TMUADiagnosticService.checkpoint(section, in: modelContext)
        }
    }

    private func submit() {
        // A second tap while the sheet is closing must not resubmit.
        guard section.status == .inProgress else { return }
        act {
            try TMUADiagnosticService.submit(section, in: snapshot, in: modelContext)
            if snapshot.diagnostic.initialCompletedAt != nil, snapshot.currentRound > 0,
               snapshot.sections.allSatisfy({ $0.status == .submitted }) {
                try TMUAProgrammeService.completeRefinementTasks(settings: settings, in: modelContext)
                if let content = TMUAContentStore.context(),
                   try TMUAProgrammeService.load(settings: settings, in: modelContext) != nil {
                    try TMUAProgrammeService.generateOrRefresh(settings: settings, content: content, resourceSessions: true, in: modelContext)
                }
            }
        }
        showingSubmit = false
        if section.status == .submitted { dismiss() }
    }

    private func act(_ operation: () throws -> Void) {
        do {
            try operation()
            savedPulse.toggle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static var debugOverview: Bool {
#if DEBUG
        DebugTMUAScenarioService.value("--tmua-open") == "overview"
#else
        false
#endif
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Answer options, evenly and compactly spaced.
struct TMUAOptionList<Row: View>: View {
    let options: [TMUAOption]
    @ViewBuilder let row: (TMUAOption) -> Row

    var body: some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.id) { option in row(option) }
        }
        .padding(.top, 2)
    }
}

/// A discreet source credit under the options, visually subordinate to the mathematics.
struct TMUASourceCredit: View {
    let content: TMUAContentItem

    var body: some View {
        Text(content.creditLine)
            .font(.caption)
            .foregroundStyle(RevisrColors.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("question.source")
    }
}

struct TMUAOptionButton: View {
    let option: TMUAOption
    let selected: Bool
    var state: Marking = .neutral
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var badge: CGFloat = 28

    enum Marking {
        case neutral, correct, incorrect, key
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: RevisrSpacing.compact) {
                Text(option.id)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: badge, height: badge)
                    .foregroundStyle(selected ? Color.white : RevisrColors.primaryLabel)
                    .background(selected ? (state == .neutral ? RevisrColors.accentFill : accent)
                                : RevisrColors.tertiaryBackground, in: Circle())
                MathText(option.text, role: .option)
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(accent)
                }
            }
            .padding(.vertical, RevisrSpacing.compact)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(RevisrColors.secondaryBackground, in: RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius)
                    .strokeBorder(selected || state != .neutral ? accent : .clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: RevisrMetrics.standardCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Option \(option.id): \(MathMarkup.spoken(option.text))")
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("option.\(option.id)")
    }

    private var accent: Color {
        switch state {
        case .neutral: RevisrColors.accentStrong
        case .correct, .key: RevisrColors.success
        case .incorrect: RevisrColors.critical
        }
    }

    private var symbol: String? {
        switch state {
        case .neutral: nil
        case .correct, .key: "checkmark.circle.fill"
        case .incorrect: "xmark.circle.fill"
        }
    }

    private var accessibilityState: String {
        switch state {
        case .neutral: selected ? "Selected" : ""
        case .correct: "Your answer, correct"
        case .incorrect: "Your answer, incorrect"
        case .key: "Correct answer"
        }
    }
}

/// Shows only the icon at accessibility text sizes; VoiceOver still reads the title.
struct AdaptiveLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            Label(configuration).labelStyle(.iconOnly)
        } else {
            Label(configuration).labelStyle(.titleAndIcon)
        }
    }
}

/// The system bordered style, with a disabled state that stays visible. Over the bar, iOS draws a
/// disabled bordered button as a flat black (dark mode) or white (light mode) disc with an almost
/// invisible symbol; this keeps its shape in the system's tertiary fill with a tertiary-label
/// symbol, the colours iOS uses for unavailable controls. It is still a disabled `Button`, so
/// VoiceOver reads it as dimmed.
struct TMUABorderedControlStyle: PrimitiveButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        if isEnabled {
            Button(configuration).buttonStyle(.bordered)
        } else {
            Button(configuration).buttonStyle(DisabledLook())
        }
    }

    private struct DisabledLook: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
    }
}
