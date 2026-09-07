import Foundation

/// A count with its noun, for text that has to pass through a plain `String`.
///
/// `Text("^[\(n) card](inflect: true)")` handles this on its own, but only for a string
/// literal handed straight to `Text`. Once the words go through a `String` — a view's
/// parameter, a message built by concatenation — the markup is never resolved and the
/// reader sees the markup itself.
func counted(_ count: Int, _ singular: String, plural: String? = nil) -> String {
    "\(count) \(count == 1 ? singular : plural ?? singular + "s")"
}
