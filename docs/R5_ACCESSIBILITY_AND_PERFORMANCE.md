# R5 · Accessibility and performance

## Accessibility

**Suite.** `TMUAStudentScreensAccessibilityUITests` runs Xcode's accessibility audit on Practice (filters set), Saved, Today, a worksheet and a worksheet question. Each screen is audited at the default text size and at the largest accessibility size (AX5, `UICTContentSizeCategoryAccessibilityXXXL`).

**Policy.** As in R2–R4: element descriptions, hit regions and traits fail the test; other issues are recorded as advisories and attached.

**Results** (no enforced failure in any run):

| Device | Appearance | Default text | Largest text |
|---|---|---|---|
| iPhone 17 Pro ("Revisr Flexible TMUA QA") | Light | Passed | Passed (after a test-scrolling fix; see below) |
| iPhone 17 Pro | Dark | Passed | Passed |
| iPhone 16e (smallest supported screen in use) | Light | Passed | Passed |
| iPhone 17 Pro Max | Light | Passed | Passed |

The first largest-text run failed only because the test looked for the Marking filter after it had scrolled out of a lazily loaded list. The test now scrolls to each filter; the app was unchanged.

**Advisories recorded** (counts per screen, iPhone 17 Pro, light, default text):

| Screen | Advisories |
|---|---:|
| Practice | 9 |
| Saved | 8 |
| Today | 13 |
| Worksheet | 10 |
| Worksheet question | 11 |

At AX5 there are 0–3 per screen. The types:

- **Contrast.** Mostly elements the audit cannot name (system bars and backgrounds, as in the R2–R4 baselines), plus "nearly passed" on secondary footnote text.
- **Dynamic Type partially unsupported.** On list section headers and footers and some secondary labels, which do resize (see the AX5 screenshots).
- **Text clipped.** Reported on "Clear filters", "Start", "Start with question 1", "Targeted practice" and "Consolidation". The Practice screenshots show "Clear filters" in full at both sizes, and the other labels are short single words or phrases. These were not all checked visually, so they remain recorded advisories.

**Visual inspection** of the filter rows: screenshots kept in the test results, not committed, and showing filter controls and question references only.

- Default text, iPhone 16e: every filter value is in full on one line, "Self-marked with solution" included.
- AX5, dark: each value wraps under its title ("Marking" / "Self-marked with solution"); nothing is truncated.

**VoiceOver labels checked by tests:**

| Element | What it reads |
|---|---|
| Filters | "title, value", read by the tests through `value` |
| Self-marking buttons | Outcome titles; the chosen one adds the value "Recorded" (the selected trait is not exposed through a bordered button in a list grid) |
| Worksheet question rows | Number, paper and question label, publisher, level, page and result |
| Worksheet header | Kind, size, sources and state |
| Finished worksheet | The tick is hidden from VoiceOver; it read "Selected" before R5 |
| Saved | Section headers carry identifiers and counts |
| Source credits | Combined with the question header ("Source: …") |
| Paper rows | Say how many questions open in Revisr |

**Not claimed:**

- **Full compliance.** The advisories above remain.
- **Real VoiceOver navigation.** Not tested on a device.
- **PDF pages.** These are third-party content shown by PDFKit, and were not audited.

## Performance

Measured in `TMUAStudentExperienceTests.testPrintPerformanceOfCatalogueAndPractice`. This is a Debug build on the iPhone 17 Pro simulator, so absolute times are indicative; a Release build on a device is faster.

| Operation | Time |
|---|---:|
| Build the library and catalogue from the bundled manifests (uncached) | 60.6 ms |
| Index a busy student's progress (467 results, 246 flags) | 1.0 ms |
| Practice filter over 2,697 questions, any status (worst of six statuses: "not attempted") | 2.5–6.8 ms |
| Worksheet candidates over the whole catalogue | 14.6 ms |
| 2,851 identity lookups | 2.0 ms |

R5 code changes behind these numbers, all measured above:

- **Cached lists.** `practicable` and `automatic` are now stored on the catalogue. In R4, each use filtered all 2,851 entries again.
- **Per-source index.** `entries(inSource:)` reads an index instead of scanning; the R4 question screen scanned all entries three times per render.
- **Fewer passes.** Practice skips the reserved-question filter when nothing is reserved, and Saved reads each question's latest result once per render.

The catalogue is built once per launch and cached; R4 behaviour is kept. PDFs open only when the student asks. No PDF is preloaded.

**Programme generation.** The heaviest plan (180 days at 12 hours a week, bundled library, with library sessions) took 3.88 s to generate and 3.84 s to refresh, in the same Debug simulator build. Generation runs on the main actor when the student taps Refresh, so a refresh of a very long, heavy plan pauses the interface for a few seconds in a Debug build. Moving generation off the main actor is a candidate for a later milestone; R5 did not change where it runs.
