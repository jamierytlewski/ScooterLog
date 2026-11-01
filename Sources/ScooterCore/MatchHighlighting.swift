import Foundation

public enum MatchHighlighting {
    /// Emphasizes the UTF-16 `ranges` MapKit reports for the text the rider typed.
    /// Ranges that do not fit the text are ignored instead of trapping.
    public static func attributed(_ text: String, ranges: [NSRange]) -> AttributedString {
        var result = AttributedString(text)
        for nsRange in ranges {
            guard let range = Range(nsRange, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result),
                  lower < upper else { continue }
            result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return result
    }
}
