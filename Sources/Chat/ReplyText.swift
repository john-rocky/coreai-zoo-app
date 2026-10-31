import Foundation

/// The assistant bubble's answer and thinking as the kit's stream builds them. Thinking deltas go
/// to the thinking field and response deltas to the answer, with one rule on top: a reply that
/// reasons without opening a thinking block and ends that reasoning with a lone `</think>`. With
/// Think off the prompt ends outside a block (LFM3's template closes it as `<think></think>`), so
/// the kit's stream passes that reasoning and the marker as answer text. As soon as the marker has
/// arrived, and while the thinking field is still empty, the text before it moves to the thinking
/// field and the marker goes; later deltas go to the answer. The end of the reply applies the
/// same rule once more.
struct ReplyText: Equatable {
    var content = ""
    var thinking = ""

    static let closeMarker = "</think>"

    mutating func addResponse(_ delta: String) {
        content += delta
        moveLateThinking()
    }

    mutating func addThinking(_ delta: String) {
        thinking += delta
    }

    mutating func finish() {
        moveLateThinking()
    }

    private mutating func moveLateThinking() {
        guard thinking.isEmpty, let close = content.range(of: Self.closeMarker) else { return }
        thinking = content[..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        content = String(content[close.upperBound...].drop { $0.isWhitespace })
    }
}
