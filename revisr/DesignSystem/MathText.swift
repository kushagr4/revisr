import SwiftUI

// MARK: - Parsing

/// A small, safe TeX subset for question text. Anything outside `\( … \)` (inline) and
/// `\[ … \]` (displayed) is plain Unicode text; unknown commands render as their literal
/// name rather than failing, so malformed content stays readable.
indirect enum MathNode: Equatable {
    /// Mathematical text: letters are set in italic as variables.
    case text(String)
    /// Upright text inside mathematics: `\text{…}` and function names such as sin and log.
    case roman(String)
    case superscript([MathNode])
    case `subscript`([MathNode])
    case fraction([MathNode], [MathNode])
    case root([MathNode])
    case binomial([MathNode], [MathNode])
    case integral(lower: [MathNode], upper: [MathNode])
}

enum MathSegment: Equatable {
    case text(String)
    case math([MathNode])
    case display([MathNode])
}

enum MathMarkup {
    static let symbols: [String: String] = [
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠", "lt": "<", "gt": ">",
        "pi": "π", "theta": "θ", "alpha": "α", "beta": "β", "gamma": "γ", "lambda": "λ", "mu": "μ",
        "phi": "φ", "omega": "ω", "sigma": "σ", "Delta": "Δ",
        "times": "×", "cdot": "·", "div": "÷", "pm": "±", "mp": "∓", "infty": "∞",
        "sin": "sin", "cos": "cos", "tan": "tan", "log": "log", "ln": "ln",
        "Rightarrow": "⇒", "Leftarrow": "⇐", "iff": "⇔", "to": "→", "forall": "∀", "exists": "∃",
        "neg": "¬", "in": "∈", "approx": "≈", "equiv": "≡", "circ": "°", "degree": "°",
        "ldots": "…", "dots": "…", "cdots": "⋯", "mid": "|", "quad": "  ", ",": "\u{2009}",
        ";": " ", " ": " ", "{": "{", "}": "}", "%": "%", "left": "", "right": "",
        "cup": "∪", "cap": "∩", "subset": "⊂", "subseteq": "⊆", "emptyset": "∅", "notin": "∉",
        "angle": "∠", "perp": "⟂", "prime": "′", "displaystyle": "", "textstyle": "", "limits": "", "!": ""
    ]

    static let functionNames: Set<String> = ["sin", "cos", "tan", "log", "ln", "exp", "min", "max"]

    static func segments(_ source: String) -> [MathSegment] {
        var result: [MathSegment] = []
        var remaining = Substring(source)
        while true {
            let inline = remaining.range(of: "\\(")
            let display = remaining.range(of: "\\[")
            guard let open = [inline, display].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) else { break }
            let isDisplay = open == display
            if open.lowerBound > remaining.startIndex {
                result.append(.text(String(remaining[..<open.lowerBound])))
            }
            let afterOpen = remaining[open.upperBound...]
            guard let close = afterOpen.range(of: isDisplay ? "\\]" : "\\)") else {
                result.append(.text(String(remaining[open.lowerBound...])))
                return result
            }
            let nodes = parse(String(afterOpen[..<close.lowerBound]).trimmingCharacters(in: .whitespaces))
            result.append(isDisplay ? .display(nodes) : .math(nodes))
            remaining = afterOpen[close.upperBound...]
        }
        if !remaining.isEmpty { result.append(.text(String(remaining))) }
        return result
    }

    /// The source split into lines. A single newline starts a new line; a blank line starts a
    /// new paragraph; a displayed equation always takes a line of its own.
    static func lines(_ source: String) -> [MathLine] {
        // A displayed equation may span several source lines.
        var unwrapped = ""
        var rest = Substring(source)
        while let open = rest.range(of: "\\["),
              let close = rest.range(of: "\\]", range: open.upperBound..<rest.endIndex) {
            unwrapped += rest[..<open.upperBound]
            unwrapped += rest[open.upperBound..<close.lowerBound].replacingOccurrences(of: "\n", with: " ")
            unwrapped += rest[close.lowerBound..<close.upperBound]
            rest = rest[close.upperBound...]
        }
        unwrapped += rest
        var result: [MathLine] = []
        var paragraphBreak = false
        for line in unwrapped.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                paragraphBreak = !result.isEmpty
                continue
            }
            var inline: [MathSegment] = []
            func flush() {
                let words = MathWord.words(in: inline)
                if !words.isEmpty {
                    result.append(MathLine(content: .words(words), startsParagraph: paragraphBreak))
                    paragraphBreak = false
                }
                inline = []
            }
            for segment in segments(line) {
                if case let .display(nodes) = segment {
                    flush()
                    result.append(MathLine(content: .display(nodes), startsParagraph: paragraphBreak))
                    paragraphBreak = false
                } else {
                    inline.append(segment)
                }
            }
            flush()
        }
        return result
    }

    static func parse(_ expression: String) -> [MathNode] {
        var parser = Parser(characters: Array(expression))
        return parser.parseSequence(until: nil)
    }

    private struct Parser {
        let characters: [Character]
        var index = 0

        mutating func parseSequence(until terminator: Character?) -> [MathNode] {
            var nodes: [MathNode] = []
            var buffer = ""
            func flush() {
                if !buffer.isEmpty { nodes.append(.text(buffer)); buffer = "" }
            }
            while index < characters.count {
                let character = characters[index]
                if let terminator, character == terminator { index += 1; break }
                switch character {
                case "\\":
                    index += 1
                    let name = readCommandName()
                    flush()
                    nodes.append(contentsOf: command(name))
                case "^":
                    index += 1
                    flush()
                    nodes.append(.superscript(readArgument()))
                case "_":
                    index += 1
                    flush()
                    nodes.append(.subscript(readArgument()))
                case "{":
                    index += 1
                    flush()
                    nodes.append(contentsOf: parseSequence(until: "}"))
                case "}":
                    index += 1
                default:
                    buffer.append(character == "-" ? "−" : character)
                    index += 1
                }
            }
            flush()
            return nodes
        }

        mutating func readCommandName() -> String {
            guard index < characters.count else { return "" }
            if !characters[index].isLetter {
                defer { index += 1 }
                return String(characters[index])
            }
            var name = ""
            while index < characters.count, characters[index].isLetter {
                name.append(characters[index])
                index += 1
            }
            return name
        }

        mutating func readArgument() -> [MathNode] {
            skipSpaces()
            guard index < characters.count else { return [] }
            if characters[index] == "{" {
                index += 1
                return parseSequence(until: "}")
            }
            if characters[index] == "\\" {
                index += 1
                return command(readCommandName())
            }
            defer { index += 1 }
            return [.text(characters[index] == "-" ? "−" : String(characters[index]))]
        }

        mutating func readRawArgument() -> String {
            skipSpaces()
            guard index < characters.count, characters[index] == "{" else { return "" }
            index += 1
            var depth = 1
            var text = ""
            while index < characters.count {
                let character = characters[index]
                index += 1
                if character == "{" { depth += 1 }
                if character == "}" { depth -= 1; if depth == 0 { break } }
                text.append(character)
            }
            return text
        }

        mutating func skipSpaces() {
            while index < characters.count, characters[index] == " " { index += 1 }
        }

        mutating func command(_ name: String) -> [MathNode] {
            switch name {
            case "frac", "dfrac", "tfrac":
                let numerator = readArgument()
                return [.fraction(numerator, readArgument())]
            case "sqrt":
                return [.root(readArgument())]
            case "binom":
                let top = readArgument()
                return [.binomial(top, readArgument())]
            case "text", "mathrm", "textrm":
                return [.roman(readRawArgument())]
            case "int":
                var lower: [MathNode] = []
                var upper: [MathNode] = []
                for _ in 0..<2 {
                    skipSpaces()
                    guard index < characters.count else { break }
                    if characters[index] == "_" { index += 1; lower = readArgument() }
                    else if characters[index] == "^" { index += 1; upper = readArgument() }
                }
                return [.integral(lower: lower, upper: upper)]
            default:
                if MathMarkup.functionNames.contains(name) {
                    // Like TeX, the space after a function name is absorbed; a thin space follows it.
                    skipSpaces()
                    return [.roman(name + "\u{2009}")]
                }
                if let symbol = MathMarkup.symbols[name] {
                    return symbol.isEmpty ? [] : [.text(symbol)]
                }
                return [.roman(name)]
            }
        }
    }

    // MARK: Spoken form

    static func spoken(_ source: String) -> String {
        segments(source).map { segment -> String in
            switch segment {
            case let .text(text): spokenUnicode(text)
            case let .math(nodes), let .display(nodes): spoken(nodes)
            }
        }.joined().replacingOccurrences(of: "  ", with: " ")
    }

    static func spoken(_ nodes: [MathNode]) -> String {
        nodes.map { node -> String in
            switch node {
            case let .text(text), let .roman(text): spokenUnicode(text)
            case let .superscript(power):
                switch flatText(power) {
                case "2": " squared "
                case "3": " cubed "
                default: " to the power \(spoken(power)) "
                }
            case let .subscript(index): " sub \(spoken(index)) "
            case let .fraction(top, bottom): " \(spoken(top)) over \(spoken(bottom)) "
            case let .root(content): " square root of \(spoken(content)) "
            case let .binomial(top, bottom): " \(spoken(top)) choose \(spoken(bottom)) "
            case let .integral(lower, upper):
                lower.isEmpty && upper.isEmpty ? " integral of "
                    : " integral from \(spoken(lower)) to \(spoken(upper)) of "
            }
        }.joined()
    }

    private static let spokenCharacters: [Character: String] = [
        "²": " squared ", "³": " cubed ", "√": " square root of ", "∛": " cube root of ", "∜": " fourth root of ",
        "−": " minus ", "≤": " less than or equal to ", "≈": " approximately equal to ", "·": " times ",
        "≥": " greater than or equal to ", "≠": " not equal to ", "×": " times ", "÷": " divided by ",
        "±": " plus or minus ", "π": " pi ", "θ": " theta ", "∞": " infinity ", "⇒": " implies ",
        "⇔": " if and only if ", "∀": " for all ", "∃": " there exists ", "°": " degrees ", "ⁿ": " to the power n ",
        "ˣ": " to the power x ", "⁻": " minus ", "¹": " to the power 1 ", "⁰": " to the power 0 ",
        "₁": " sub 1 ", "₂": " sub 2 ", "₀": " sub 0 ", "₋": " sub minus ",
        "⁴": " to the power 4 ", "⁵": " to the power 5 ", "⁶": " to the power 6 ", "⁷": " to the power 7 ",
        "⁸": " to the power 8 ", "⁹": " to the power 9 ", "′": " prime ", "″": " double prime ",
        "∠": " angle ", "⟂": " is perpendicular to ", "↔": " corresponds to ", "→": " to ", "∫": " integral of ",
        "…": " and so on ", "∪": " union ", "∩": " intersection ", "⊂": " is a subset of ",
        "⊆": " is a subset of or equal to ", "∅": " the empty set ", "∉": " is not in ", "∈": " is in "
    ]

    static func spokenUnicode(_ text: String) -> String {
        var result = ""
        for character in text {
            if let replacement = spokenCharacters[character] { result += replacement } else { result.append(character) }
        }
        return result
    }

    /// Latin letters and lower-case Greek letters in mathematics are variables, set in italic.
    static func isVariableLetter(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return false }
        return ("a"..."z").contains(character) || ("A"..."Z").contains(character)
            || (0x03B1...0x03C9).contains(scalar.value)
    }

    static func flatText(_ nodes: [MathNode]) -> String? {
        var text = ""
        for node in nodes {
            switch node {
            case let .text(value), let .roman(value): text += value
            default: return nil
            }
        }
        return text
    }
}

// MARK: - Layout model

/// One line of question text: wrapped words, or a displayed equation.
struct MathLine: Equatable {
    enum Content: Equatable {
        case words([MathWord])
        case display([MathNode])
    }

    let content: Content
    let startsParagraph: Bool
}

/// A run of text and maths that stays on one line, so punctuation stays attached to the
/// expression before it. Long inline expressions are split into several words after
/// top-level relations and operators, which is where a line may break.
struct MathWord: Equatable {
    var pieces: [MathSegment]
    var trailingSpace: Bool

    static func words(in paragraph: String) -> [MathWord] {
        words(in: MathMarkup.segments(paragraph))
    }

    static func words(in segments: [MathSegment]) -> [MathWord] {
        var words: [MathWord] = []
        var current: [MathSegment] = []
        func finish(space: Bool) {
            if !current.isEmpty { words.append(MathWord(pieces: current, trailingSpace: space)) }
            current = []
        }
        for segment in segments {
            switch segment {
            case let .math(nodes), let .display(nodes):
                let chunks = breakableChunks(nodes)
                for (offset, chunk) in chunks.enumerated() {
                    current.append(.math(chunk))
                    if offset < chunks.count - 1 { finish(space: false) }
                }
            case let .text(text):
                var buffer = ""
                for character in text {
                    if character == " " {
                        if !buffer.isEmpty { current.append(.text(buffer)); buffer = "" }
                        finish(space: true)
                    } else {
                        buffer.append(character)
                    }
                }
                if !buffer.isEmpty { current.append(.text(buffer)) }
            }
        }
        finish(space: false)
        return words
    }

    /// Characters after which an inline expression may break, as in TeX: relations and
    /// binary operators that are followed by a space, outside brackets and modulus signs.
    static let breakAfter: Set<Character> = ["=", "<", ">", "≤", "≥", "≠", "≈", "≡", "⇒", "⇐", "⇔", "→",
                                             "+", "−", "×", "±", "∓", "·"]

    /// Expressions shorter than this many visible characters never break, and a fragment
    /// shorter than `minimumFragment` joins its neighbour, so "x > 0" never splits.
    static let minimumBreakableLength = 14
    static let minimumFragment = 4

    static func breakableChunks(_ nodes: [MathNode]) -> [[MathNode]] {
        guard visibleLength(nodes) >= minimumBreakableLength else { return [nodes] }
        var merged: [[MathNode]] = []
        for chunk in rawChunks(nodes) {
            if let last = merged.last, visibleLength(last) < minimumFragment {
                merged[merged.count - 1] = last + chunk
            } else {
                merged.append(chunk)
            }
        }
        if merged.count > 1, let last = merged.last, visibleLength(last) < minimumFragment {
            merged.removeLast()
            merged[merged.count - 1] += last
        }
        return merged
    }

    /// Approximate printed width in characters, ignoring spaces.
    static func visibleLength(_ nodes: [MathNode]) -> Int {
        nodes.reduce(0) { total, node in
            switch node {
            case let .text(text), let .roman(text): total + text.filter { $0 != " " }.count
            case let .superscript(inner), let .subscript(inner): total + visibleLength(inner)
            case let .fraction(top, bottom), let .binomial(top, bottom):
                total + max(visibleLength(top), visibleLength(bottom))
            case let .root(inner): total + 1 + visibleLength(inner)
            case let .integral(lower, upper): total + 1 + max(visibleLength(lower), visibleLength(upper))
            }
        }
    }

    private static func rawChunks(_ nodes: [MathNode]) -> [[MathNode]] {
        var chunks: [[MathNode]] = []
        var chunk: [MathNode] = []
        var depth = 0
        var insideModulus = false
        for node in nodes {
            guard case let .text(text) = node else {
                chunk.append(node)
                continue
            }
            var buffer = ""
            var characters = Array(text)[...]
            while let character = characters.popFirst() {
                buffer.append(character)
                switch character {
                case "(", "[": depth += 1
                case ")", "]": depth = max(0, depth - 1)
                case "|": insideModulus.toggle()
                default: break
                }
                if depth == 0, !insideModulus, breakAfter.contains(character), characters.first == " " {
                    while characters.first == " " { buffer.append(characters.removeFirst()) }
                    if !characters.isEmpty || node != nodes.last {
                        chunk.append(.text(buffer))
                        chunks.append(chunk)
                        chunk = []
                        buffer = ""
                    }
                }
            }
            if !buffer.isEmpty { chunk.append(.text(buffer)) }
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        return chunks.isEmpty ? [nodes] : chunks
    }
}

// MARK: - Metrics

/// Type roles for question content. The sizes are the values at the default text size;
/// every size, offset and rule scales with Dynamic Type relative to the role's text style.
enum MathTextRole {
    case question
    case option
    case solution
    case body

    var baseSize: CGFloat {
        switch self {
        case .question: 18
        case .option, .body: 17
        case .solution: 16
        }
    }
}

/// Font size and the measurements derived from it, so superscripts, fractions and rules
/// keep their proportions at every text size.
struct MathMetrics: Equatable {
    var size: CGFloat
    var base: CGFloat
    var weight: Font.Weight = .regular
    var display = false

    var font: Font { .system(size: size, weight: weight) }
    var displayed: MathMetrics { MathMetrics(size: size, base: base, weight: weight, display: true) }
    var script: MathMetrics { scaled(0.72) }
    var fractionPart: MathMetrics { display ? scaled(0.94, keepDisplay: false) : scaled(0.8) }
    var superscriptRaise: CGFloat { size * 0.36 }
    var subscriptDrop: CGFloat { size * 0.18 }
    /// Height of the fraction bar and minus sign above the baseline.
    var axis: CGFloat { size * 0.3 }
    var rule: CGFloat { max(1, (size * 0.055).rounded(.toNearestOrAwayFromZero)) }
    var lineGap: CGFloat { (size * 0.3).rounded() }
    var paragraphGap: CGFloat { (size * 0.75).rounded() }

    private func scaled(_ factor: CGFloat, keepDisplay: Bool = false) -> MathMetrics {
        MathMetrics(size: max(base * 0.55, size * factor), base: base, weight: weight,
                    display: keepDisplay && display)
    }
}

// MARK: - Rendering

/// Renders question text with inline and displayed mathematics, wrapping like prose and
/// respecting Dynamic Type. VoiceOver reads a spoken description.
struct MathText: View {
    let source: String
    var role: MathTextRole
    var weight: Font.Weight
    @ScaledMetric(relativeTo: .body) private var bodyScale: CGFloat = 1
    @ScaledMetric(relativeTo: .callout) private var calloutScale: CGFloat = 1

    init(_ source: String, role: MathTextRole = .body, weight: Font.Weight = .regular) {
        self.source = source
        self.role = role
        self.weight = weight
    }

    private var metrics: MathMetrics {
        let size = role.baseSize * (role == .solution ? calloutScale : bodyScale)
        return MathMetrics(size: size, base: size, weight: weight)
    }

    var body: some View {
        let metrics = metrics
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(MathMarkup.lines(source).enumerated()), id: \.offset) { index, line in
                lineView(line, metrics: metrics)
                    .padding(.top, index == 0 ? 0 : line.startsParagraph ? metrics.paragraphGap : metrics.lineGap)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MathMarkup.spoken(source))
    }

    @ViewBuilder
    private func lineView(_ line: MathLine, metrics: MathMetrics) -> some View {
        switch line.content {
        case let .words(words):
            MathFlowLayout(lineSpacing: metrics.lineGap) {
                ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                    MathWordView(word: word, metrics: metrics)
                }
            }
        case let .display(nodes):
            MathOverflow {
                MathNodesView(nodes: nodes, metrics: metrics.displayed).fixedSize()
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, metrics.lineGap)
        }
    }
}

private struct MathWordView: View {
    let word: MathWord
    let metrics: MathMetrics

    var body: some View {
        if word.pieces.contains(where: { if case .math = $0 { true } else { false } }) {
            MathOverflow { row }
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(word.pieces.enumerated()), id: \.offset) { _, piece in
                switch piece {
                case let .text(text): Text(text).font(metrics.font)
                case let .math(nodes), let .display(nodes): MathNodesView(nodes: nodes, metrics: metrics)
                }
            }
            if word.trailingSpace { Text(" ").font(metrics.font) }
        }
        .fixedSize()
    }
}

/// Shows content at its natural width when it fits, and otherwise lets it scroll sideways
/// rather than run off the screen. Inline expressions normally break before this is needed.
private struct MathOverflow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            content
            ScrollView(.horizontal) { content }
        }
    }
}

private struct MathNodesView: View {
    let nodes: [MathNode]
    let metrics: MathMetrics

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                switch group {
                case let .inline(run): inlineText(run)
                case let .block(node): block(node)
                }
            }
        }
    }

    private enum Group {
        case inline([MathNode])
        case block(MathNode)
    }

    /// Text, superscripts and subscripts join into one `Text`; fractions, roots, binomials
    /// and integrals need stacked layout.
    private var groups: [Group] {
        var result: [Group] = []
        var run: [MathNode] = []
        for node in nodes {
            switch node {
            case .text, .roman: run.append(node)
            case let .superscript(inner), let .subscript(inner):
                if MathMarkup.flatText(inner) != nil { run.append(node) } else {
                    if !run.isEmpty { result.append(.inline(run)); run = [] }
                    result.append(.block(node))
                }
            default:
                if !run.isEmpty { result.append(.inline(run)); run = [] }
                result.append(.block(node))
            }
        }
        if !run.isEmpty { result.append(.inline(run)) }
        return result
    }

    private func inlineText(_ run: [MathNode]) -> Text {
        run.reduce(Text("")) { partial, node in
            switch node {
            case let .text(text):
                return partial + Self.variables(text, metrics: metrics)
            case let .roman(text):
                return partial + Text(text).font(metrics.font)
            case let .superscript(inner):
                return partial + Self.scriptText(inner, metrics: metrics.script).baselineOffset(metrics.superscriptRaise)
            case let .subscript(inner):
                return partial + Self.scriptText(inner, metrics: metrics.script).baselineOffset(-metrics.subscriptDrop)
            default:
                return partial
            }
        }
    }

    private static func scriptText(_ nodes: [MathNode], metrics: MathMetrics) -> Text {
        nodes.reduce(Text("")) { partial, node in
            switch node {
            case let .text(text): partial + variables(text, metrics: metrics)
            case let .roman(text): partial + Text(text).font(metrics.font)
            default: partial
            }
        }
    }

    /// Latin letters and lower-case Greek letters are variables and are set in italic;
    /// digits, operators and punctuation stay upright.
    static func variables(_ text: String, metrics: MathMetrics) -> Text {
        var result = Text("")
        var run = ""
        var runIsVariable = false
        func flush() {
            guard !run.isEmpty else { return }
            let piece = Text(run).font(metrics.font)
            result = result + (runIsVariable ? piece.italic() : piece)
            run = ""
        }
        for character in text {
            let isVariable = MathMarkup.isVariableLetter(character)
            if isVariable != runIsVariable { flush(); runIsVariable = isVariable }
            run.append(character)
        }
        flush()
        return result
    }

    @ViewBuilder
    private func block(_ node: MathNode) -> some View {
        switch node {
        case let .fraction(top, bottom):
            let part = metrics.fractionPart
            MathFractionLayout(gap: metrics.size * 0.1, rule: metrics.rule, axis: metrics.axis,
                               overhang: metrics.size * 0.1) {
                MathNodesView(nodes: top, metrics: part).fixedSize()
                Rectangle()
                MathNodesView(nodes: bottom, metrics: part).fixedSize()
            }
        case let .root(content):
            MathRadical(metrics: metrics) {
                MathNodesView(nodes: content, metrics: metrics).fixedSize()
            }
        case let .binomial(top, bottom):
            let part = metrics.fractionPart
            VStack(spacing: metrics.size * 0.15) {
                MathNodesView(nodes: top, metrics: part).fixedSize()
                MathNodesView(nodes: bottom, metrics: part).fixedSize()
            }
            .padding(.horizontal, metrics.size * 0.32)
            .overlay {
                HStack {
                    MathParenthesis(opening: true).stroke(.primary, lineWidth: metrics.rule)
                        .frame(width: metrics.size * 0.22)
                    Spacer(minLength: 0)
                    MathParenthesis(opening: false).stroke(.primary, lineWidth: metrics.rule)
                        .frame(width: metrics.size * 0.22)
                }
            }
            .fixedSize()
            .alignmentGuide(.firstTextBaseline) { $0.height / 2 + metrics.axis }
        case let .integral(lower, upper):
            HStack(alignment: .center, spacing: metrics.size * 0.05) {
                Text("∫").font(.system(size: metrics.size * 1.45, weight: .light))
                VStack(alignment: .leading, spacing: metrics.size * 0.3) {
                    MathNodesView(nodes: upper, metrics: metrics.script)
                    MathNodesView(nodes: lower, metrics: metrics.script)
                }
            }
            .fixedSize()
            .alignmentGuide(.firstTextBaseline) { $0.height / 2 + metrics.axis }
        case let .superscript(inner):
            MathNodesView(nodes: inner, metrics: metrics.script)
                .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] + metrics.superscriptRaise }
        case let .subscript(inner):
            MathNodesView(nodes: inner, metrics: metrics.script)
                .alignmentGuide(.firstTextBaseline) { $0[.firstTextBaseline] - metrics.subscriptDrop }
        case let .text(text):
            Self.variables(text, metrics: metrics)
        case let .roman(text):
            Text(text).font(metrics.font)
        }
    }
}

/// Numerator, bar and denominator, with the bar on the mathematical axis so a fraction
/// sits on the same baseline as the text around it.
struct MathFractionLayout: Layout {
    var gap: CGFloat
    var rule: CGFloat
    var axis: CGFloat
    var overhang: CGFloat

    private func parts(_ subviews: Subviews) -> (top: CGSize, bottom: CGSize, width: CGFloat) {
        let top = subviews[0].sizeThatFits(.unspecified)
        let bottom = subviews[2].sizeThatFits(.unspecified)
        return (top, bottom, max(top.width, bottom.width) + 2 * overhang)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let parts = parts(subviews)
        return CGSize(width: parts.width, height: parts.top.height + parts.bottom.height + 2 * gap + rule)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let parts = parts(subviews)
        subviews[0].place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: ProposedViewSize(parts.top))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + parts.top.height + gap),
                          proposal: ProposedViewSize(width: parts.width, height: rule))
        subviews[2].place(at: CGPoint(x: bounds.midX, y: bounds.minY + parts.top.height + 2 * gap + rule),
                          anchor: .top, proposal: ProposedViewSize(parts.bottom))
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline else { return nil }
        return bounds.minY + parts(subviews).top.height + gap + rule / 2 + axis
    }
}

/// A radical sign drawn to the height of its contents, with a bar over them.
private struct MathRadical<Content: View>: View {
    let metrics: MathMetrics
    @ViewBuilder let content: Content

    var body: some View {
        let sign = metrics.size * 0.5
        let clearance = metrics.size * 0.12 + metrics.rule
        content
            .padding(.leading, sign + metrics.size * 0.06)
            .padding(.trailing, metrics.size * 0.06)
            .padding(.top, clearance)
            .background(alignment: .topLeading) {
                MathRadicalSign(signWidth: sign).stroke(.primary, style: StrokeStyle(lineWidth: metrics.rule, lineJoin: .round))
            }
            .fixedSize()
    }
}

private struct MathRadicalSign: Shape {
    let signWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = rect.minY + 0.5
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.62))
        path.addLine(to: CGPoint(x: rect.minX + signWidth * 0.25, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + signWidth * 0.55, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + signWidth, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: top))
        return path
    }
}

private struct MathParenthesis: Shape {
    let opening: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let outer = opening ? rect.maxX : rect.minX
        let inner = opening ? rect.minX : rect.maxX
        path.move(to: CGPoint(x: outer, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: outer, y: rect.maxY), control: CGPoint(x: inner, y: rect.midY))
        return path
    }
}

/// Wraps words like prose and aligns each line on the text baseline. A word wider than the
/// line is offered the line width, so it can scroll instead of overflowing.
struct MathFlowLayout: Layout {
    var lineSpacing: CGFloat

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var ascents: [CGFloat] = []
        var width: CGFloat = 0
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var proposal = ProposedViewSize.unspecified
            var size = subviews[index].sizeThatFits(proposal)
            if size.width > width {
                proposal = ProposedViewSize(width: width, height: nil)
                size = subviews[index].sizeThatFits(proposal)
            }
            let ascent = subviews[index].dimensions(in: proposal)[VerticalAlignment.firstTextBaseline]
            if !row.indices.isEmpty && row.width + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += size.width
            row.ascent = max(row.ascent, ascent)
            row.descent = max(row.descent, size.height - ascent)
            row.indices.append(index)
            row.sizes.append(size)
            row.ascents.append(ascent)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let computed = rows(for: subviews, width: width)
        let height = computed.reduce(0) { $0 + $1.ascent + $1.descent }
            + CGFloat(max(0, computed.count - 1)) * lineSpacing
        let usedWidth = computed.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? usedWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for (position, index) in row.indices.enumerated() {
                let size = row.sizes[position]
                subviews[index].place(at: CGPoint(x: x, y: y + row.ascent - row.ascents[position]),
                                      proposal: ProposedViewSize(size))
                x += size.width
            }
            y += row.ascent + row.descent + lineSpacing
        }
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        let computed = rows(for: subviews, width: bounds.width)
        guard let first = computed.first else { return nil }
        if guide == .firstTextBaseline { return bounds.minY + first.ascent }
        if guide == .lastTextBaseline {
            let above = computed.dropLast().reduce(0) { $0 + $1.ascent + $1.descent + lineSpacing }
            return bounds.minY + above + (computed.last?.ascent ?? 0)
        }
        return nil
    }
}
