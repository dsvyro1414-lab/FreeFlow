import Foundation

public enum TranscriptSanitizer {
  private static let fillerPattern = try! NSRegularExpression(
    pattern: #"(?i)(?:,\s*)?(?<![\p{L}-])(?:uh+|um+|erm+|hmm+)(?![\p{L}-])(?:\s*,)?"#
  )
  private static let repeatedWhitespace = try! NSRegularExpression(pattern: #"[\t ]+"#)
  private static let spaceBeforePunctuation = try! NSRegularExpression(pattern: #"\s+([,.;:!?])"#)

  public static func removingAcousticFillers(from transcript: String) -> String {
    let fullRange = NSRange(transcript.startIndex..., in: transcript)
    var result = fillerPattern.stringByReplacingMatches(
      in: transcript,
      range: fullRange,
      withTemplate: " "
    )

    result = replace(repeatedWhitespace, in: result, with: " ")
    result = replace(spaceBeforePunctuation, in: result, with: "$1")
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func replace(
    _ expression: NSRegularExpression,
    in value: String,
    with replacement: String
  ) -> String {
    expression.stringByReplacingMatches(
      in: value,
      range: NSRange(value.startIndex..., in: value),
      withTemplate: replacement
    )
  }
}
