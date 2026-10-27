# R2 mathematical UI and accessibility

27 October 2026. Two question-screen issues from the previous milestone:
- Xcode's accessibility audit reported "Dynamic Type font sizes are partially unsupported" for 152 question-screen elements in the journey audit;
- the disabled Back button was hard to see in dark mode.

All results are from the iPhone 17 Pro simulator (iOS 26.5). None comes from a physical iPhone.

## Dynamic Type advisories

### How they were measured

A new focused UI test, `TMUAQuestionAccessibilityAuditUITests.testQuestionScreenSupportsDynamicType`, opens each of the ten layout specimens on the real diagnostic question screen and runs Xcode's audit for Dynamic Type and clipped text. It records every reported element with its frame and the audit's own description.

The specimens are fixed by number:
- **Why:** the R2 selector orders a fresh profile's questions differently on every launch, so the debug layout scenario now opens specimen N whatever its position.
- **Consequence:** counts before and after the change cover the same ten screens. The earlier journey figure of 152 covered one fixture question and is not comparable.

### What produced them

| Element | Count before | Cause |
|---|---:|---|
| Words, spaces and formula runs of the question and its options | 1,120 | The renderer (`MathText`) draws each word as its own `Text` with `Font.system(size:)`. The size came from `@ScaledMetric`, so it did grow with the setting, but the font carried no text style. The audit reports such text as "User will not be able to change the font size of this element". |
| "Question n of N" and the progress bar | 20 | The progress header is capped at accessibility size 1 on purpose, so the question gets the screen at the largest sizes. These are flagged correctly, and the cap is kept. |
| Clipped text | 0 | — |

VoiceOver was never affected: `MathText` is one accessibility element with a spoken description. The audit inspects the underlying text runs as well.

### Was it a genuine limitation?

Partly.
- **Not a real failure to resize.** On the simulator, changing the text size live while a question was open resized all the text, including fractions and the modulus formula. The text was not stuck.
- **A real absence of semantic scaling.** The fonts were bare point sizes. The platform could not tell that they follow Dynamic Type, which is the property the audit checks and assistive technology relies on.

### The change

Every renderer font is now built by `UIFontMetrics.scaledFont(for:)` for the role's text style: body for questions and options, callout for worked solutions. Such a font declares the Dynamic Type style it follows.

Three details matter:
1. **The size still follows the text style.** `scaledFont(for:)` alone scales an arbitrary size less steeply than the text style itself: an 18 pt question would be 39 pt at accessibility size XL, where body text is 40 pt. The first attempt made questions about 8% smaller at the largest sizes; screenshots caught it and it was corrected. The renderer now feeds `scaledFont` the input that lands on the style's own growth, so an 18 pt question is 42 pt at XL and 56 pt at the largest size, never smaller than body text. A unit test (`testQuestionTextGrowsLikeBodyText`) enforces this.
2. **Layout uses the drawn size.** Superscript offsets, fraction bars, gaps and line spacing are computed from the font's actual point size, which UIKit rounds to whole points. An earlier draft computed them from a separately scaled value that drifted from the drawn glyphs at large sizes (39.3 against 37 pt). `testDrawnSizeMatchesLayoutAndFollowsTheTextStyle` now requires the two to agree at every size.
3. **The design is unchanged:** an 18 pt question, 17 pt options and 16 pt solutions at the default size, scripts at 0.72 and fractions at 0.8. There is no `scaleEffect`, no rasterised text and no cap on question text.

### Result

Same ten specimens, default text size, light mode:

| | Before R2 | After R2 |
|---|---:|---:|
| Dynamic Type advisories from question and option text | 1,120 | 22 |
| of which prose words | most of them | 0 |
| Capped header (intentional) | 20 | 20 |
| Clipped text | 0 | 0 |

The 22 that remain:
- **17 nodes the audit cannot name.** It reports no element for them.
- **3 unbreakable formulas.** `|f(x) − f(y)| ≤ |x − y|`, `x² − 7x + 10 = 0` and part of a long identity, each drawn inside the sideways-scrolling fallback for formulas wider than the line.
- **A full stop and a space** that follow a formula.

The formulas resized with the surrounding text when the text-size setting was changed live on the simulator. The unnamed nodes cannot be inspected, so whether they are a limit of the audit or a real gap is not established. The test now fails if any word of prose is flagged, or if the total exceeds 24.

The journey-wide audit (`TMUAAccessibilityAuditUITests`, one fixture question) agrees:
- the question screen falls from 152 Dynamic Type advisories to 4;
- the screen behind the pause overlay falls from 152 to 4;
- all screens together fall from 602 advisories to 307.

The remaining paused-screen contrast notes are expected: they come from text behind the translucent overlay, as recorded in R1.

Layout is unchanged (`TMUAQuestionTypographyUITests`, light and dark):
- **Default size:** every specimen's measurements match the previous redesign within 1 pt.
- **AX3:** they match within 2 pt.
- **Width:** every stem stays within 354 pt on the 402 pt screen.

## Disabled Back button

On the first question the Previous button is disabled. Over the bar, iOS 26 draws a disabled bordered button as a flat disc with an almost invisible chevron:
- pure black (0, 0, 0) on a 19-grey bar in dark mode;
- near-white (250) on a 247-grey bar in light mode, so it was nearly invisible in light mode too.

The fix is a small button style, `TMUABorderedControlStyle`, applied to that one button:
- **Enabled:** the unchanged system bordered button.
- **Disabled:** the same capsule, drawn in the system's tertiary fill with a tertiary-label chevron (the colours iOS uses for unavailable controls). Measured disc colour: 42–45 grey on the 19-grey bar in dark mode, 232 on 247 in light mode.

It is still a disabled `Button`: the UI test sees it as not enabled, which VoiceOver announces as dimmed. No VoiceOver session was run. `testDisabledPreviousButtonStaysRecognisable` checks four things:
- the button is disabled on question 1 and enabled on question 2;
- its label is "Previous question";
- its frame is the same in both states (68 × 58 pt), so the bar does not shift;
- it passes in light and dark mode.

Nothing else in the bar changed.

## Preserved

These were re-measured with the existing typography test:
- the compact header;
- reading-size question text that wraps naturally;
- formulas that stay within the screen (every stem at most 354 pt wide on a 402 pt screen, at the default size and AX3);
- superscripts and fractions on their baselines;
- readable options;
- the discreet credit line.
