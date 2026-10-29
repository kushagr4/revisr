# R5 · Questions tab: Practice, Papers, Sources, Saved

The four-view structure from R4 is unchanged. R5 fixes what made it hard to use: filters that reset, truncated values, imprecise labels, statuses that ignored real work, and identity gaps.

## Practice

- **Filters kept.** Filters live in the Questions tab (`TMUAPracticeFilters`), so switching to Saved or Papers and back keeps them. "Clear filters" appears once any filter is set.
- **Readable filter rows.** `TMUAFilterMenu` puts the title and value side by side when they fit. Otherwise the value wraps on its own line, so it is never truncated.
  - VoiceOver reads "title, value", for example "Marking, Self-marked with solution".
  - R4's "Self-marked with solution" truncation is fixed without shortening any label.
  - Inspected in screenshots at the default and the largest text size, in light and dark mode, on the iPhone 16e, iPhone 17 Pro and iPhone 17 Pro Max.
- **Filters available.**
  - Paper (All, Paper 1, Paper 2).
  - Topic: the 17 syllabus topics, plus "Topic not yet classified" and "Beyond the TMUA specification", now separate.
  - Strand: shown once a topic is chosen. It matches questions Revisr marks and provisionally classified questions that carry a strand; the footer says so whenever a strand is chosen.
  - Marking: "Marked by Revisr", "Self-marked with solution", "Self-recorded (no solution)".
  - Source.
  - Difficulty: "Level 3 · Challenging" and so on; every level is an estimate.
  - Status, described below.
- **Status uses every kind of result.**
  - Revisr-marked practice answers.
  - Submitted diagnostic answers (new in R5).
  - The student's own recorded results.

  | Status | Matches |
  |---|---|
  | Not attempted | No result of any kind |
  | Attempted | A result other than Skipped |
  | Previously incorrect | The latest result is incorrect or partly right |
  | Not yet checked | The latest result is "Not yet checked" |
  | Flagged for review | Flagged under any identity |

  Ties go to the result Revisr marked. The row says "last: incorrect (your marking)" for self-recorded results.

  A later "Skipped" never hides an earlier mistake: the status looks at the latest result actually worked, and a question only ever skipped counts as not attempted.
- **Open screens stay open.** Practice and Saved rows are navigation values, as Today's are. Recording a result that moves a question out of a filtered list or a Saved section no longer closes its open screen.
- **Order.** Revisr-marked questions first, then the library's own order: paper by paper, question by question. Before R5 the order was by ID, which put MAT Q2–Q7 before Q1A–Q1J.
- **Rows.** Each row shows its paper and question label, its paper fit ("(estimated)" when the index judged it) and its topic ("(provisional)" for drafts, "Topic not yet classified", or "Beyond the TMUA specification"). It also shows the estimated level, the marking method and the last result.

## Papers

- **Filters.**
  - Exam: TMUA (official), TMUA mocks, MAT, STEP, CSAT, UKMT competitions.
  - Publisher.
  - Year.
  - "Only papers with solutions".

  All are kept when switching views.
- **Question counts are honest.** The subtitle gives the paper's question count. The access line says how many of those open in Revisr:
  - "All 20 open in Revisr (personal study copy) · 12 marked by Revisr, the rest self-marked";
  - "None of the 20 open in Revisr · on UKMT's website";
  - "no solutions in this build, so record your own results".
- **Paper detail.** Rows show the syllabus topic, with its provenance, instead of the index's label. A question waiting in an open diagnostic round is locked ("available once you submit it"), including when the paper is opened from a planned paper session.
- **Order.** Questions in a paper are listed in document order: paper part, then page, then number. A combined Paper 1 + Paper 2 file lists each paper in turn, and a file that numbers questions per section or per year keeps each section together.

## Sources

Unchanged in substance. Credits and links come only from the verified provider registry. Every provider page states "Revisr is not affiliated with or endorsed by …". No URL was added.

## Saved

Sections, each a list of catalogue questions:

1. **Worksheets in progress:** started and unfinished, opening the worksheet.
2. **Flagged for review.**
3. **Previously incorrect:** the latest result was incorrect or partly right, including self-marked results, labelled as such.
4. **Not yet checked.**
5. **Recently attempted:** the 50 most recent.

The practice screen's flag toggle now also reads and clears every identity. Progress counts one question once, however many identities its results were saved under.

A question is matched by every identity it has had: its catalogue ID, the bank item that marks it, and a merged reprint's earlier ID. It therefore stays in Saved after re-indexing or merging. `testStatusFiltersAndSavedIdentityAcrossAliases` checks a flag and a result saved under an earlier ID.

## Progress tab

A new "Self-marked practice" section shows:

- the questions recorded;
- correct by the student's marking, incorrect or partly right, not yet checked and skipped;
- worksheets finished.

It says these never count as evidence of mastery. The Revisr-marked section is now titled "Marked by Revisr".

## Copy that now matches behaviour

R4 said self-marked results "count towards your progress and plan". In fact they only excluded questions from future worksheets.

R5 changes both the behaviour and the copy. A question marked incorrect or partly right can come back once in a later worksheet; whole-paper results stop that paper being set again; neither is ever evidence of topic mastery. The copy now says exactly this.
