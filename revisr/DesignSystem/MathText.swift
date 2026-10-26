import SwiftUI

// MARK: - Parsing

/// A small, safe TeX subset for question text. Anything outside `\( … \)` is
/// plain Unicode text; unknown commands render as their literal name rather
/// than failing, so malformed content stays readable.
indirect enum MathNode: Equatable {
    case text(String)
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
        ";": " ", " ": " ", "{": "{", "}": "}", "%": "%", "left": "", "right": ""
    ]

    static func segments(_ source: String) -> [MathSegment] {
        var result: [MathSegment] = []
        var remaining = Substring(source)
        while let open = remaining.range(of: "\\(") {
            if open.lowerBound > remaining.startIndex {
                result.append(.text(String(remaining[..<open.lowerBound])))
            }
            let afterOpen = remaining[open.upperBound...]
            guard let close = afterOpen.range(of: "\\)") else {
                result.append(.text(String(remaining[open.lowerBound...])))
                return result
            }
            result.append(.math(parse(String(afterOpen[..<close.lowerBound]))))
            remaining = afterOpen[close.upperBound...]
        }
        if !remaining.isEmpty { result.append(.text(String(remaining))) }
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
                return [.text(readRawArgument())]
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
                if let symbol = MathMarkup.symbols[name] {
                    let spaced = ["sin", "cos", "tan", "log", "ln"].contains(name) ? symbol + "\u{2009}" : symbol
                    return spaced.isEmpty ? [] : [.text(spaced)]
                }
                return [.text(name)]
            }
        }
    }

    // MARK: Spoken form

    static func spoken(_ source: String) -> String {
        segments(source).map { segment -> String in
            switch segment {
            case let .text(text): spokenUnicode(text)
            case let .math(nodes): spoken(nodes)
            }
        }.joined().replacingOccurrences(of: "  ", with: " ")
    }

    static func spoken(_ nodes: [MathNode]) -> String {
        nodes.map { node -> String in
            switch node {
            case let .text(text): spokenUnicode(text)
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
        "²": " squared ", "³": " cubed ", "√": " square root of ", "−": " minus ", "≤": " less than or equal to ",
        "≥": " greater than or equal to ", "≠": " not equal to ", "×": " times ", "÷": " divided by ",
        "±": " plus or minus ", "π": " pi ", "θ": " theta ", "∞": " infinity ", "⇒": " implies ",
        "⇔": " if and only if ", "∀": " for all ", "∃": " there exists ", "°": " degrees ", "ⁿ": " to the power n ",
        "ˣ": " to the power x ", "⁻": " minus ", "¹": " to the power 1 ", "⁰": " to the power 0 ",
        "₁": " sub 1 ", "₂": " sub 2 ", "₀": " sub 0 ", "₋": " sub minus "
    ]

    static func spokenUnicode(_ text: String) -> String {
        var result = ""
        for character in text {
            if let replacement = spokenCharacters[character] { result += replacement } else { result.append(character) }
        }
        return result
    }

    static func flatText(_ nodes: [MathNode]) -> String? {
        var text = ""
        for node in nodes {
            guard case let .text(value) = node else { return nil }
            text += value
        }
        return text
    }
}

// MARK: - Rendering

/// Renders question text with inline mathematics, wrapping like prose and
/// respecting Dynamic Type. VoiceOver reads a spoken description.
struct MathText: View {
    let source: String
    var textStyle: Font.TextStyle = .body
    var weight: Font.Weight = .regular

    init(_ source: String, textStyle: Font.TextStyle = .body, weight: Font.Weight = .regular) {
        self.source = source
        self.textStyle = textStyle
        self.weight = weight
    }

    var body: some View {
        let paragraphs = source.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                if paragraph.trimmingCharacters(in: .whitespaces).isEmpty {
                    Spacer().frame(height: 2)
                } else {
                    MathFlowLayout(spacing: 0, lineSpacing: 4) {
                        ForEach(Array(MathWord.words(in: paragraph).enumerated()), id: \.offset) { _, word in
                            MathWordView(word: word, textStyle: textStyle, weight: weight)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MathMarkup.spoken(source))
    }
}

/// A run of text and maths with no whitespace inside, so punctuation stays
/// attached to the expression before it when lines wrap.
struct MathWord {
    var pieces: [MathSegment]
    var trailingSpace: Bool

    static func words(in paragraph: String) -> [MathWord] {
        var words: [MathWord] = []
        var current: [MathSegment] = []
        func finish(space: Bool) {
            if !current.isEmpty { words.append(MathWord(pieces: current, trailingSpace: space)) }
            current = []
        }
        for segment in MathMarkup.segments(paragraph) {
            switch segment {
            case let .math(nodes):
                current.append(.math(nodes))
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
}

private struct MathWordView: View {
    let word: MathWord
    let textStyle: Font.TextStyle
    let weight: Font.Weight

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(word.pieces.enumerated()), id: \.offset) { _, piece in
                switch piece {
                case let .text(text): Text(text).font(.system(textStyle, weight: weight))
                case let .math(nodes): MathNodesView(nodes: nodes, textStyle: textStyle, weight: weight)
                }
            }
            if word.trailingSpace { Text(" ").font(.system(textStyle, weight: weight)) }
        }
        .fixedSize()
    }
}

private struct MathNodesView: View {
    let nodes: [MathNode]
    let textStyle: Font.TextStyle
    let weight: Font.Weight

    private var smallStyle: Font.TextStyle {
        switch textStyle {
        case .largeTitle, .title: .title3
        case .title2, .title3: .body
        case .headline, .body, .callout: .footnote
        default: .caption2
        }
    }

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

    /// Text, superscripts and subscripts join into one `Text`; fractions,
    /// roots, binomials and integrals need stacked layout.
    private var groups: [Group] {
        var result: [Group] = []
        var run: [MathNode] = []
        for node in nodes {
            switch node {
            case .text: run.append(node)
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
                return partial + Text(text).font(.system(textStyle, weight: weight))
            case let .superscript(inner):
                return partial + Text(MathMarkup.flatText(inner) ?? "")
                    .font(.system(smallStyle, weight: weight)).baselineOffset(7)
            case let .subscript(inner):
                return partial + Text(MathMarkup.flatText(inner) ?? "")
                    .font(.system(smallStyle, weight: weight)).baselineOffset(-3)
            default:
                return partial
            }
        }
    }

    @ViewBuilder
    private func block(_ node: MathNode) -> some View {
        switch node {
        case let .fraction(top, bottom):
            VStack(spacing: 1) {
                MathNodesView(nodes: top, textStyle: smallStyle, weight: weight)
                Rectangle().frame(height: 1)
                MathNodesView(nodes: bottom, textStyle: smallStyle, weight: weight)
            }
            .fixedSize()
            .padding(.horizontal, 1)
            .alignmentGuide(.firstTextBaseline) { dimensions in dimensions.height / 2 + 5 }
        case let .root(content):
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("√").font(.system(textStyle, weight: weight))
                MathNodesView(nodes: content, textStyle: textStyle, weight: weight)
                    .padding(.top, 2)
                    .overlay(alignment: .top) { Rectangle().frame(height: 1) }
            }
        case let .binomial(top, bottom):
            HStack(alignment: .center, spacing: 1) {
                Text("(").font(.system(textStyle, weight: .light)).scaleEffect(y: 1.6)
                VStack(spacing: 2) {
                    MathNodesView(nodes: top, textStyle: smallStyle, weight: weight)
                    MathNodesView(nodes: bottom, textStyle: smallStyle, weight: weight)
                }
                Text(")").font(.system(textStyle, weight: .light)).scaleEffect(y: 1.6)
            }
            .fixedSize()
            .alignmentGuide(.firstTextBaseline) { dimensions in dimensions.height / 2 + 5 }
        case let .integral(lower, upper):
            HStack(alignment: .center, spacing: 1) {
                Text("∫").font(.system(textStyle, weight: .light)).scaleEffect(y: 1.4)
                VStack(alignment: .leading, spacing: 4) {
                    MathNodesView(nodes: upper, textStyle: smallStyle, weight: weight)
                    MathNodesView(nodes: lower, textStyle: smallStyle, weight: weight)
                }
            }
            .fixedSize()
            .alignmentGuide(.firstTextBaseline) { dimensions in dimensions.height / 2 + 5 }
        case let .superscript(inner):
            MathNodesView(nodes: inner, textStyle: smallStyle, weight: weight).offset(y: -7)
        case let .subscript(inner):
            MathNodesView(nodes: inner, textStyle: smallStyle, weight: weight).offset(y: 3)
        case let .text(text):
            Text(text).font(.system(textStyle, weight: weight))
        }
    }
}

/// Wraps words like prose and aligns each line on the text baseline.
struct MathFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let dimensions = subviews[index].dimensions(in: .unspecified)
            let ascent = dimensions[VerticalAlignment.firstTextBaseline]
            if !row.indices.isEmpty && row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.ascent = max(row.ascent, ascent)
            row.descent = max(row.descent, size.height - ascent)
            row.indices.append(index)
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
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let ascent = subviews[index].dimensions(in: .unspecified)[VerticalAlignment.firstTextBaseline]
                subviews[index].place(at: CGPoint(x: x, y: y + row.ascent - ascent),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.ascent + row.descent + lineSpacing
        }
    }
}
