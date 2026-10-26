import XCTest
@testable import revisr

/// VoiceOver reads question text through `MathMarkup.spoken`. Every
/// mathematical symbol used by bundled questions must have a spoken form, or
/// VoiceOver falls back to reading Unicode names or nothing.
@MainActor
final class TMUAMathSpeechTests: XCTestCase {
    /// Typographic characters that VoiceOver already reads sensibly.
    private let typographic: Set<Character> = ["—", "–", "’", "‘", "“", "”"]

    func testEverySymbolInBundledQuestionsHasASpokenForm() throws {
        guard let content = TMUAContentStore.context(), !content.bank.items.isEmpty else {
            throw XCTSkip("No bundled bank in this build")
        }
        var unspoken: [Character: String] = [:]
        for item in content.bank.items {
            let text = ([item.stem, item.solution] + item.options.map(\.text)).joined(separator: " ")
            for character in Set(text) where !character.isASCII && !character.isLetter && !typographic.contains(character) {
                if MathMarkup.spoken(String(character)).trimmingCharacters(in: .whitespaces) == String(character) {
                    unspoken[character] = item.versionKey
                }
            }
        }
        XCTAssertTrue(unspoken.isEmpty, "symbols without a spoken form: \(unspoken.map { "\($0.key) (e.g. \($0.value))" })")
    }

    func testSpokenFormsForCommonNotation() {
        XCTAssertEqual(squash(MathMarkup.spoken("∛8 = 2")), "cube root of 8 = 2")
        XCTAssertEqual(squash(MathMarkup.spoken("f′(x) ≥ 0")), "f prime (x) greater than or equal to 0")
        XCTAssertEqual(squash(MathMarkup.spoken("\\(\\frac{1}{2}\\)")), "1 over 2")
        XCTAssertEqual(squash(MathMarkup.spoken("10·3")), "10 times 3")
    }

    private func squash(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
