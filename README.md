# Revisr

Revisr is a local-first iPhone admissions-preparation app built with SwiftUI, SwiftData, PDFKit, and Apple system frameworks. TMUA is the active preparation domain; CSAT is represented in the architecture but remains inactive until TMUA preparation is complete.

The five tabs provide the current TMUA programme day, the full 30-day plan, attempt and latest-question analytics, TMUA topics/specification coverage, and local settings/source management. The private installation includes 1,573 question records, 530 programme assignments across 30 days, all 80 validated question-paper PDFs, and a local Solution Bank built from 66 unique supplied solution PDFs plus two already-bundled combined books. Questions, papers, and available solutions work offline; development archives and reports are not included in the app.

Open `revisr.xcodeproj` in Xcode. The project targets iOS 17 or later and has no package, account, analytics, advertising, cloud, or runtime-network dependency.

## Private installation

Revisr is for private local use and is not distributed through TestFlight or the App Store.

1. Open `revisr.xcodeproj` in Xcode.
2. Connect and unlock the intended iPhone.
3. Select the `revisr` target and confirm automatic signing uses team `JLX428R3Y7`.
4. Select the connected iPhone as the destination.
5. Build and run with Command-R.

Keep bundle identifier `com.kushagra.revisr` so later Xcode builds upgrade the existing installation and preserve its container. Do not routinely uninstall the app. Before migration-heavy updates, retain a device-container backup using the procedure recorded in `RELEASE_READINESS.md`.

See `ADMISSIONS_IMPORT.md` and `SOLUTION_BANK.md` for deterministic resource workflows, and `RELEASE_READINESS.md` for migration, device, regression, and private-use readiness evidence.
