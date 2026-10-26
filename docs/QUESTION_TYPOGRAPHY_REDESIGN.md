# Question typography redesign

Long questions were displayed as oversized, poorly wrapped headings. This redesign fixes the renderer (`revisr/DesignSystem/MathText.swift`) and the question screens. It does not change the app's global fonts and never caps the question text's Dynamic Type size.

## What was wrong

Measured with synthetic layout specimens on the approved iPhone 17 Pro simulator (402 × 874 pt) before the change:

1. **Heading-sized question text.** Every stem used `.title3` (20 pt by default and growing fastest with larger text). A five-line Paper 2 proof filled the screen before the first option (option A at 762 pt).
2. **Long inline expressions could not wrap.** A whole `\( … \)` expression was one unbreakable run, so long sums and identities ran off the right edge. Measured stem widths were 428 and 405 pt on a 402 pt screen, and 911 and 853 pt at a large accessibility size.
3. **Fixed-point offsets did not scale.** Superscript (7 pt) and subscript (3 pt) offsets and the fraction baseline nudge (5 pt) were constants. At large text sizes `u₁` and `x²` sat almost on the baseline and fractions drifted.
4. **Displayed equations were not supported.** `\[ … \]` showed as raw TeX.
5. **Chrome took space from the question.** At accessibility sizes the progress header stacked onto three lines (about 200 pt). The source label sat above the question as its first line, and options had 16 pt padding with a 56 pt minimum height.

## What changed

### Renderer

- **Scale roles:** `MathTextRole` replaces text styles.

  | Role | Size at default text size | Scales with |
  |---|---:|---|
  | Question statement | 18 pt | Body |
  | Answer option | 17 pt | Body |
  | Worked solution | 16 pt | Callout |
  | Question number and progress | 13 pt (footnote, semibold) | Footnote, capped at AX1 in the header only |
  | Source credit | 12 pt (caption) | Caption |

- **Proportional metrics:** `MathMetrics` derives every size from the current font size:
  - scripts at 0.72×;
  - inline fraction parts at 0.8× (0.94× in displayed equations);
  - superscript raise at 0.36 em and subscript drop at 0.18 em;
  - fraction bar on the mathematical axis at 0.3 em, with a rule of about 0.055 em.

  Nothing is a fixed point offset, and there is no `scaleEffect`.
- **Fractions** use a custom layout (`MathFractionLayout`) that reports its true baseline, so a fraction sits on the line with the surrounding text.
- **Roots and binomial brackets** are drawn to the height of their contents (`MathRadical`, `MathParenthesis`). There are no stretched glyphs.
- **Line breaking like TeX.** A long inline expression may break after a top-level relation or binary operator followed by a space (`=`, `<`, `≤`, `⇒`, `+`, `−`, `×`, …), never inside brackets or modulus signs. Expressions under 14 visible characters never break, and a fragment under 4 characters joins its neighbour, so "x > 0" stays whole.
- **Last-resort overflow.** A formula still wider than the line (for example a long product of fractions) scrolls sideways instead of overflowing the screen.
- **Displayed equations.** `\[ … \]` is centred on its own line, may span source lines, and scrolls sideways if needed.
- **Typography conventions:**
  - Latin and lower-case Greek letters in mathematics are italic, as variables.
  - `\text{…}` and function names (sin, cos, tan, log, ln, exp, min, max) are upright, and the space after a function name is absorbed as in TeX.
- **Paragraphs:** a newline starts a line (0.3 em gap); a blank line starts a paragraph (0.75 em gap).
- **VoiceOver:** the spoken description is unchanged, and new symbols have spoken forms: ∪, ∩, ⊂, ⊆, ∅, ∉, ∈.

### Question screens (diagnostic, practice, review)

- **Hierarchy:** compact progress ("Question 3 of 10", timer, saved) in one footnote-sized row, then the statement at reading size, then the options. The source credit sits under the options in caption size.
- **Options:** 12 pt vertical and 14 pt horizontal padding, 10 pt spacing, a 52 pt minimum height (above the 44 pt tap target), and a 28 pt letter badge that scales with text size and is aligned to the first line's baseline.
- **Chrome capped, content not:** the header is capped at accessibility size 1 and the button bar at size 2, so at the largest sizes the question gets the screen. "Review and submit" shortens to "Review" instead of truncating.
- **Official questions:** these are shown as printed (see `RESOURCE_LIBRARY_INTEGRATION.md`), full width, with a zoomable full-screen view and a lettered answer grid.

## Before and after

`revisrUITests/TMUAQuestionTypographyUITests` opens ten synthetic specimens inside the real diagnostic screen. They cover a short algebra question, fractions and roots, a displayed equation, long options, several paragraphs, a long inline sum, statements I–III, a numbered proof, a modulus definition and long-sentence options. For each it records the stem frame and the first option's position.

| Specimen (default text size) | Stem height before → after (pt) | First option top before → after (pt) | Stem width before → after (pt, screen 402) |
|---|---|---|---|
| Paper 1 Q1, displayed equation | 160 → 153 | 429 → 375 | 347 → 319 (raw TeX before) |
| Paper 1 Q4, long inline sum | 226 → 209 | 496 → 430 | **428 → 347** (overflowed before) |
| Paper 1 Q5, short algebra | 56 → 50 | 326 → 272 | 247 → 343 |
| Paper 2 Q3, paragraphs and fractions | 291 → 245 | 561 → 467 | 350 → 347 |
| Paper 2 Q4, numbered proof | 493 → 400 | 762 → 622 | **405 → 353** (overflowed before) |
| Paper 2 Q5, statements I–III | 224 → 201 | 494 → 423 | 346 → 340 |

At the largest size tested (accessibility XL):
- **Before:** two specimens overflowed, at 911 and 853 pt wide.
- **After:** none overflows; every stem is at most 354 pt wide.
- **Height:** stems are somewhat taller, because expressions now wrap instead of running off the edge.
- **First option:** appears up to 158 pt earlier, because the header no longer stacks.
- **Size:** question text keeps scaling, about 1.6× its default size or more.

Screenshots (light and dark, default and AX3) are kept as test attachments and were reviewed by eye. They are not committed, because they would add binary noise; rerun the test to regenerate them.

## Tests

- `revisrTests/TMUA/MathTextLayoutTests` (10 tests):
  - short expressions never break;
  - long ones break only after top-level operators, never inside brackets or modulus signs;
  - displayed equations take their own line;
  - paragraph and line spacing;
  - upright function names and italic variables;
  - metrics scale proportionally;
  - the question role is a reading size, not a heading;
  - a long question stays within its width and keeps scaling at AX3;
  - an unbreakable formula never widens the layout.
- `revisrUITests/TMUAQuestionTypographyUITests`:
  - every specimen, at default and AX3 sizes, must stay within the screen width;
  - an official question shown as printed must also fit, carry its credit, and open a zoom view.
- `revisrTests/TMUA/TMUAMathSpeechTests` (existing): every symbol in the bundled bank has a spoken form.

## Known limits

- **No full TeX engine:** large operators with limits beyond the integral, matrices and `\mathbb` are not supported. Unknown commands render their name so content stays readable.
- **Official questions are small:** shown as printed, they inherit the paper's roughly 10 pt type, which renders at about 7.5 pt across the phone's width. The zoom view covers this. Re-typesetting official questions natively would need a licence for any public use.
