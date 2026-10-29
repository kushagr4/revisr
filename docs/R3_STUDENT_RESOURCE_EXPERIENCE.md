# R3 student resource experience

28 October 2026. What a student sees when a build has few or no approved questions, and how external papers fit into study. All observations come from the iPhone 17 Pro simulator (iOS 26.5); none comes from a physical iPhone.

## The gap R3 found

A public build bundles only approved questions, and today there are none. Walking the journey in that state (`--tmua-public-content`, a DEBUG-only switch that applies the public gate to the bundled bank) showed three problems:

1. **A new student could not finish setup.** On the last onboarding step every diagnostic length was disabled, so no length could be chosen, and the "Choose a length" button never became enabled. The student was held there with no way forward.
2. **The library was unreachable.** "Papers & sources" sits in the Questions tab, and the tabs appear only once a plan exists, which needs a diagnostic. A public user would never see the 83 papers linked from UAT-UK, Oxford, OCR and UKMT.
3. **Independent preparation sites were invisible.** Providers whose own sites offer free papers (`publicAccess: provider` in the provider register) were not shown in any public screen.

## What changed

| Where | Before | After |
|---|---|---|
| Onboarding, length step | The same long warning repeated on four dimmed cards; the button stayed disabled | When no length is available, the reason appears once, at full contrast, above the cards. The button reads "Save and browse papers" and saves the exam date and availability. When some lengths are available, nothing changes |
| Diagnostic hub, no diagnostic | Reason plus "Choose a different length", which led nowhere | Reason; "Choose a different length" only when some length is available; a "Browse papers and sources" link to the library, explaining that sources open on publishers' websites and that self-recorded results are not evidence of mastery |
| Library | Official papers and other listed sources | Adds "Other preparation sites": JZMaths, TMUA.co.uk, TMUA Euclid and Tyler Tutoring, each with its credit, a terms summary and a link to the provider's own site. A footer says they are independent, some materials are paid, and nothing is reproduced. Their papers are not listed individually |
| Provider register | Tyler Tutoring and TMUA Euclid restricted (no verified page in R1) | Both linked: their own sites were found and checked on 28 October. MioMath stays restricted: it sells post-exam recalls of live papers |
| Diagnostic message | "No rights-cleared past or mock questions…" even when nothing at all was approved | When nothing is approved: "No questions have completed independent review and rights clearance yet… You can still browse official papers and other sources on their publishers' websites." The older message remains for the case it describes |

## What a student can do with an external paper

These capabilities already existed; R3 makes them reachable in a public build and checks them with a UI test.

| Need | How |
|---|---|
| Discover the resource | Library grouped by type (official TMUA, other admissions tests, competitions), with type and source filters |
| See accurate attribution | "Source: UAT-UK (© UCLES)" and the like on every source, with the provider's terms summary in the footer |
| Open the provider's site | A button titled with the provider's page name, which opens it in Safari |
| Identify the paper | The source title ("TMUA 2022 Paper 1"), its year, and a list of its questions with topic and page, labelled as estimates |
| Record a study session | "Record a whole-paper result": outcome, optional self-marked score and time |
| Record a raw result | The same sheet; it says it is self-marked and not used as evidence of topic mastery |
| Return to the plan | When a plan exists, a paper session is a plan task whose completion records the result and returns to Today |

Self-recorded results never become question-level evidence. They update progress and stop a finished paper from being offered again, but they never produce topic weaknesses (`TMUAResourceLog` is separate from `TMUAPracticeAttempt`).

## Plans and external papers

On a study day the approved bank cannot fill, the planner offers a self-marked paper session:
- in a public build, only from sources linked on the provider's own site;
- in a development build, from bundled study copies.

Paper sessions are never repeated, never displace question practice, and say whose website to use (`TMUAPublicContentTests.testPublicPlanAssignsOnlyApprovedQuestionsAndLinkedPapers`).

**Not built: a plan without a diagnostic.** A public build with no approved questions has no diagnostic, so it has no plan, and external papers are browsed rather than scheduled. A "papers-only" plan for that state is a product decision for the owner, listed in `R3_VALIDATION.md`.

## Verification

`revisrUITests/TMUAPublicContentUITests.testPublicBuildWithoutApprovedQuestionsStaysHonestAndUseful` walks the whole journey in public mode, light appearance:
1. all four lengths are disabled, with one shared notice, and setup completes;
2. the hub gives the reason, offers no diagnostic and no length picker, and links to the library;
3. the library says nothing is reproduced and shows no personal study copies;
4. a source shows its credit and publisher link, with no bundled paper;
5. a whole-paper result is recorded and then shown.

Claude reviewed its screenshots by eye; there was no human design review. The existing Starter first-run journey still passes with content available.
