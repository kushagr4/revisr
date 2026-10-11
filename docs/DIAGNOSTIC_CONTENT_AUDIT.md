# Diagnostic content audit

Checked 9 October 2026 against the bundled admissions and solutions manifests and the first pages of the selected PDFs. These are development resources; this audit does not establish public redistribution permission.

| Exam | Paper 1 source | Paper 2 source | Questions | Assessment basis |
| --- | --- | --- | ---: | --- |
| TMUA | `SRC-E29687FAAA262C5F` (TMUA Euclid R2DREW2 Paper 1) | `SRC-D475EB66A3CA6BF0` (TMUA Euclid Sample Paper 2) | 20 + 20 | Each paper cover says 75 minutes. Both have linked, verified local PDF mark schemes. No structured correct-option field exists, so scoring is self-marked after answer submission. These are third-party mock papers, not official future benchmarks. |
| SMC | `SRC-802E1A98D14C82D9` (2023) | `SRC-EB34C15CFA44A832` (2024) | 25 + 25 | Both papers are credited on the cover to the United Kingdom Mathematics Trust. Each says 90 minutes, starts at 25 points, gives +4 per correct answer, −1 per incorrect answer and 0 for unanswered. Both have linked, verified local PDF worked solutions. Without structured correct options, the official-style score can only be calculated from user-confirmed marking. |
| BMO | `SRC-8C463E1A9E242017` (`bmo1-2023`) | `SRC-385D3DE51F5BA6A6` (`bmo1-2024`) | 6 + 6 | Both covers credit the United Kingdom Mathematics Trust, state 3½ hours and 10 marks per question, and require written proofs. No local solution or mark-scheme relationship exists. Entered marks are explicitly self-estimated, never represented as examiner marks; the student can leave a proof unassessed. |

All 102 selected question records have a one-based question number and PDF page, `scheduleEligible = true`, `validityState = usable`, `protection = none`, and no duplicate warning. The six source PDFs are bundled. The two sources in each exam have disjoint stable question IDs. The selector must recheck these conditions at runtime and refuse an incomplete source rather than silently substitute another exam's paper.

The BMO filenames use a competition-year label one year later than the calendar date on the cover: `bmo1-2023` is dated November 2022 and `bmo1-2024` November 2023. The UI should use the verified cover date when showing a publication year, or otherwise use the source label verbatim. The current manifest has no structured per-question maximum or scoring provenance; the ten-mark limit is a policy for these two audited BMO papers only.

No question record contains a verified correct answer or option. In-app automatic answer checking would fabricate evidence. TMUA and SMC must instead lock entered options before showing the appropriate PDF mark scheme or worked solutions, then require the student to report correctness. An unmarked response is unassessed, not incorrect. BMO must accept self-estimated marks and/or proof assessment without implying an official mark. Timing information is verified from the selected papers; an elapsed timer is suitable, with no automatic expiry or forced submission.

Rights status remains unverified for every selected source and solution. Their inclusion in a development bundle must not be treated as permission to ship them publicly.
