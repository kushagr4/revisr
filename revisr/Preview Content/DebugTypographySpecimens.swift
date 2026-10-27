#if DEBUG
import Foundation

/// Synthetic layout specimens for checking question typography (`--uitest-typography-bank`).
/// They are written for layout testing, not taken from any paper, and cover the shapes real
/// questions take: short and long stems, fractions, roots, integrals, a displayed equation,
/// several paragraphs, numbered argument lines, statements I–III and long answer options.
enum DebugTypographySpecimens {
    private struct Specimen {
        let id: String
        let stem: String
        let options: [String]
        let key: String
    }

    private static let paperOne: [Specimen] = [
        Specimen(id: "spec-p1-short",
                 stem: "Find the sum of the roots of \\(x^2 - 7x + 10 = 0\\).",
                 options: ["\\(3\\)", "\\(5\\)", "\\(7\\)", "\\(10\\)", "\\(-7\\)"], key: "C"),
        Specimen(id: "spec-p1-medium",
                 stem: "The curve \\(C\\) has equation \\(y = \\frac{x^2 + 1}{\\sqrt{x}}\\) for \\(x > 0\\). The tangent to \\(C\\) at the point where \\(x = 1\\) meets the \\(x\\)-axis at \\(P\\). What is the \\(x\\)-coordinate of \\(P\\)?",
                 options: ["\\(-2\\)", "\\(-1\\)", "\\(0\\)", "\\(\\frac{1}{2}\\)", "\\(1\\)"], key: "B"),
        Specimen(id: "spec-p1-display",
                 stem: "Consider the equation\n\\[ \\frac{2x - 1}{x + 3} = \\frac{x + 2}{2x - 1} \\]\nwhere \\(x \\ne -3\\) and \\(x \\ne \\frac{1}{2}\\). How many real values of \\(x\\) satisfy the equation?",
                 options: ["\\(0\\)", "\\(1\\)", "\\(2\\)", "\\(3\\)", "\\(4\\)"], key: "C"),
        Specimen(id: "spec-p1-long-options",
                 stem: "The function \\(f\\) is defined for all real \\(x\\) by \\(f(x) = x^3 - 3x\\). Which one of the following statements about the graph of \\(y = f(x)\\) is correct?",
                 options: ["It has a local maximum at \\((-1, 2)\\) and a local minimum at \\((1, -2)\\)",
                           "It has a local minimum at \\((-1, 2)\\) and a local maximum at \\((1, -2)\\)",
                           "It has exactly one stationary point, which is a point of inflection at the origin",
                           "It is increasing for all real values of \\(x\\), so it has no stationary points",
                           "It has a local maximum at \\((1, 2)\\) and a local minimum at \\((-1, -2)\\)"], key: "A"),
        Specimen(id: "spec-p1-paragraphs",
                 stem: "A sequence is defined by \\(u_1 = 2\\) and \\(u_{n+1} = 3u_n - 2\\) for \\(n \\ge 1\\).\nThe sum of the first \\(n\\) terms is \\(S_n = 2 + 4 + 10 + 28 + \\cdots + (3^{n-1} + 1) = \\frac{3^n - 1}{2} + n\\) for every positive integer \\(n\\).\nFind the smallest value of \\(n\\) for which \\(S_n > 1000\\).",
                 options: ["\\(5\\)", "\\(6\\)", "\\(7\\)", "\\(8\\)", "\\(9\\)"], key: "C")
    ]

    private static let paperTwo: [Specimen] = [
        Specimen(id: "spec-p2-statements",
                 stem: "Consider the following statements about real numbers \\(a\\) and \\(b\\).\nI: If \\(a^2 > b^2\\), then \\(a > b\\).\nII: If \\(a > b > 0\\), then \\(\\frac{1}{a} < \\frac{1}{b}\\).\nIII: If \\(a + b\\) is irrational, then at least one of \\(a\\) and \\(b\\) is irrational.\nWhich of these statements are true?",
                 options: ["none of them", "I only", "II only", "III only", "I and II only", "I and III only",
                           "II and III only", "I, II and III"], key: "G"),
        Specimen(id: "spec-p2-proof",
                 stem: "A student attempts to prove that, for every positive integer \\(n\\), the number \\(n^2 + n + 41\\) is prime. The argument is as follows.\n(1) When \\(n = 1\\), the value is \\(43\\), which is prime.\n(2) Suppose the value is prime for some positive integer \\(k\\).\n(3) Then \\((k + 1)^2 + (k + 1) + 41 = (k^2 + k + 41) + 2(k + 1)\\).\n(4) A prime number plus an even number is prime, so the value is prime for \\(k + 1\\).\n(5) Hence, by induction, the value is prime for every positive integer \\(n\\).\nWhich one of the following best describes the argument?",
                 options: ["The argument is correct.",
                           "The argument is incorrect, and the first error is in line (1).",
                           "The argument is incorrect, and the first error is in line (3).",
                           "The argument is incorrect, and the first error is in line (4).",
                           "The argument is incorrect, and the first error is in line (5)."], key: "D"),
        Specimen(id: "spec-p2-paragraphs",
                 stem: "A function \\(f\\) defined on the real numbers is called steady if \\(|f(x) - f(y)| \\le |x - y|\\) for all real \\(x\\) and \\(y\\).\n\nThe function \\(g\\) is defined by \\(g(x) = \\frac{x}{1 + x^2}\\).\n\nWhich of the following is a necessary and sufficient condition for the function \\(h(x) = c\\,g(x)\\), where \\(c\\) is a positive constant, to be steady?",
                 options: ["\\(c \\le \\frac{1}{2}\\)", "\\(c < 1\\)", "\\(c \\le 1\\)", "\\(c \\le 2\\)",
                           "\\(h\\) is steady for every positive \\(c\\)"], key: "C"),
        Specimen(id: "spec-p2-long-options",
                 stem: "The positive integers \\(m\\) and \\(n\\) satisfy \\(mn = 360\\). Consider the claim: “if \\(m\\) is even, then \\(n\\) is odd”. Which one of the following is a counterexample to the claim?",
                 options: ["\\(m = 8\\) and \\(n = 45\\), because \\(m\\) is even and \\(n\\) is odd",
                           "\\(m = 6\\) and \\(n = 60\\), because \\(m\\) is even and \\(n\\) is even",
                           "\\(m = 45\\) and \\(n = 8\\), because \\(m\\) is odd and \\(n\\) is even",
                           "\\(m = 5\\) and \\(n = 72\\), because \\(m\\) is odd and \\(n\\) is even",
                           "There is no counterexample, because whenever \\(m\\) is even the product \\(mn\\) is even"],
                 key: "B"),
        Specimen(id: "spec-p2-short",
                 stem: "Which one of the following is the negation of “every prime number greater than \\(2\\) is odd”?",
                 options: ["Every prime number greater than \\(2\\) is even",
                           "Some prime number greater than \\(2\\) is even",
                           "Some prime number greater than \\(2\\) is odd",
                           "No prime number greater than \\(2\\) is odd",
                           "Every odd number greater than \\(2\\) is prime"], key: "B")
    ]

    /// The identity of specimen `number` (from 1) in a paper, so a UI test can open the same
    /// specimen whatever order a student-specific selection gives it.
    static func specimenID(paper: Int, number: Int) -> String? {
        let specimens = paper == 1 ? paperOne : paperTwo
        return specimens.indices.contains(number - 1) ? specimens[number - 1].id : nil
    }

    static func items(syllabus: TMUASyllabus) -> [TMUAContentItem] {
        var result: [TMUAContentItem] = []
        for (paper, specimens) in [(1, paperOne), (2, paperTwo)] {
            let topics = syllabus.topics.filter { paper == 1 ? $0.papers == [1, 2] : $0.papers.contains(2) }
                .sorted { $0.key < $1.key }
            let strands = topics.flatMap { topic in topic.strands.map { (topic.key, $0.key) } }
            for (index, specimen) in specimens.enumerated() {
                let (topic, strand) = strands[(index * 3) % strands.count]
                let letters = DebugUITestSupport.letters.prefix(specimen.options.count)
                result.append(TMUAContentItem(
                    stableId: specimen.id, version: 1, paper: paper, category: .developmentFixture,
                    title: "Layout specimen \(paper)-\(index + 1)", stem: specimen.stem,
                    options: zip(letters, specimen.options).map { TMUAOption(id: $0, text: $1) },
                    correctOptionId: specimen.key,
                    solution: "Layout specimen. The keyed answer is \(specimen.key).\nThis text exists to check how a worked solution with \\(\\frac{a}{b}\\) and \\(\\sqrt{x}\\) wraps.",
                    taxonomy: TMUATaxonomyMapping(topic: topic, strand: strand,
                        skill: paper == 2 && topic == "logic" ? "conditional-reasoning" : nil),
                    difficulty: 3, estimatedMinutes: 4, source: nil,
                    rights: TMUAContentRights(copyrightHolder: "Synthetic fixture", licence: "fixture",
                        inAppUse: .notApplicable, redistribution: .notApplicable, commercialUse: .notApplicable,
                        answerKey: .notApplicable, solution: .notApplicable,
                        attribution: TMUAContentCategory.developmentFixture.attributionTitle),
                    review: TMUAContentReview(mathematical: .none, originality: .notApplicable,
                        publication: .notApproved, editorialStatus: "layout-specimen")))
            }
        }
        return result
    }
}
#endif
