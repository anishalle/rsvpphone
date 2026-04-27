import Foundation

enum TextNormalizer {
    private static let replacements: [Character: String] = {
        let pairs: [(Character, String)] = [
            ("\u{00a0}", " "), ("\u{1680}", " "), ("\u{180e}", " "), ("\u{2000}", " "),
            ("\u{2001}", " "), ("\u{2002}", " "), ("\u{2003}", " "), ("\u{2004}", " "),
            ("\u{2005}", " "), ("\u{2006}", " "), ("\u{2007}", " "), ("\u{2008}", " "),
            ("\u{2009}", " "), ("\u{200a}", " "), ("\u{2028}", " "), ("\u{2029}", " "),
            ("\u{202f}", " "), ("\u{205f}", " "), ("\u{3000}", " "),
            ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201a}", "'"), ("\u{201b}", "'"),
            ("\u{2032}", "'"), ("\u{2035}", "'"),
            ("\u{201c}", "\""), ("\u{201d}", "\""), ("\u{201e}", "\""), ("\u{201f}", "\""),
            ("\u{00ab}", "\""), ("\u{00bb}", "\""), ("\u{2033}", "\""), ("\u{2036}", "\""),
            ("\u{2010}", "-"), ("\u{2011}", "-"), ("\u{2012}", "-"), ("\u{2013}", "-"),
            ("\u{2014}", "-"), ("\u{2015}", "-"), ("\u{2043}", "-"), ("\u{2212}", "-"),
            ("\u{2026}", "..."), ("\u{2022}", "*"), ("\u{00b7}", "*"), ("\u{2219}", "*"),
            ("\u{00a9}", "(c)"), ("\u{00ae}", "(r)"), ("\u{2122}", "TM"),
            ("\u{fb00}", "ff"), ("\u{fb01}", "fi"), ("\u{fb02}", "fl"),
            ("\u{fb03}", "ffi"), ("\u{fb04}", "ffl"), ("\u{fb05}", "st"), ("\u{fb06}", "st"),
            ("\u{fffd}", "")
        ]
        return pairs.reduce(into: [:]) { replacements, pair in
            replacements[pair.0] = pair.1
        }
    }()

    private static let trimmableEdgeCharacters = CharacterSet(charactersIn: "\"'()[]{}<>")

    static func cleanText(_ text: String) -> String {
        var replaced = ""
        replaced.reserveCapacity(text.count)
        for ch in text {
            if let replacement = replacements[ch] {
                replaced += replacement
            } else {
                replaced.append(ch)
            }
        }

        let folded = replaced
            .applyingTransform(.stripCombiningMarks, reverse: false)?
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")) ?? replaced
        let ascii = String(folded.unicodeScalars.compactMap { scalar -> Character? in
            if scalar.value == 9 || scalar.value == 10 || scalar.value == 13 { return " " }
            if scalar.value >= 32 && scalar.value <= 126 { return Character(scalar) }
            return nil
        })
        return ascii.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func directiveText(_ text: String) -> String {
        cleanText(text).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    static func cleanWords(in text: String) -> [String] {
        cleanText(text)
            .split { $0.isWhitespace }
            .compactMap { raw -> String? in
                let token = String(raw).trimmingCharacters(in: trimmableEdgeCharacters)
                guard token.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
                return token
            }
    }

    static func escapedHtmlText(_ html: String) -> String {
        var output = html
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (entity, replacement) in entities {
            output = output.replacingOccurrences(of: entity, with: replacement)
        }
        output = output.replacingOccurrences(of: "&#(\\d+);", with: "", options: .regularExpression)
        return output
    }
}
