import Foundation

enum BookParser {
    private static let maxChapterTitleChars = 64

    static func parse(url: URL) throws -> BookContent {
        let ext = url.pathExtension.lowercased()
        if ext == "epub" {
            return try EpubConverter.convert(url: url)
        }
        let data = try Data(contentsOf: url)
        let text = decodeText(data)
        if ext == "rsvp" {
            return parseRsvp(text, fallbackTitle: url.deletingPathExtension().lastPathComponent)
        }
        if ["html", "htm", "xhtml"].contains(ext) {
            return parseEvents(htmlEvents(text), title: url.deletingPathExtension().lastPathComponent, author: "")
        }
        return parsePlain(text, fallbackTitle: url.deletingPathExtension().lastPathComponent)
    }

    static func parseRsvp(_ text: String, fallbackTitle: String = "Book") -> BookContent {
        var book = BookContent(title: TextNormalizer.cleanText(fallbackTitle))
        var paragraphPending = true

        for raw in text.components(separatedBy: .newlines) {
            processRsvpLine(raw, book: &book, paragraphPending: &paragraphPending)
        }
        if !book.words.isEmpty, book.paragraphStarts.isEmpty {
            book.paragraphStarts.append(0)
        }
        if book.title.isEmpty {
            book.title = TextNormalizer.cleanText(fallbackTitle)
        }
        return book
    }

    static func parsePlain(_ text: String, fallbackTitle: String = "Book") -> BookContent {
        var book = BookContent(title: TextNormalizer.cleanText(fallbackTitle))
        var paragraphPending = true

        for raw in text.components(separatedBy: .newlines) {
            processBookLine(raw, book: &book, paragraphPending: &paragraphPending)
        }
        if !book.words.isEmpty, book.paragraphStarts.isEmpty {
            book.paragraphStarts.append(0)
        }
        return book
    }

    static func parseEvents(_ events: [(kind: String, value: String)], title: String, author: String) -> BookContent {
        var book = BookContent(title: TextNormalizer.cleanText(title), author: TextNormalizer.cleanText(author))
        for event in events {
            if event.kind == "chapter" {
                addChapterMarker(&book, title: event.value)
                continue
            }
            addParagraphMarker(&book)
            book.words.append(contentsOf: TextNormalizer.cleanWords(in: event.value))
        }
        if book.chapters.isEmpty {
            addChapterMarker(&book, title: book.title.isEmpty ? "Book" : book.title)
        }
        if !book.words.isEmpty, book.paragraphStarts.isEmpty {
            book.paragraphStarts.append(0)
        }
        return book
    }

    static func rsvpData(from book: BookContent, source: String) -> Data {
        var lines: [String] = ["@rsvp 1", "@title \(TextNormalizer.directiveText(book.title.isEmpty ? source : book.title))"]
        if !book.author.isEmpty {
            lines.append("@author \(TextNormalizer.directiveText(book.author))")
        }
        lines.append("@source \(TextNormalizer.directiveText(source))")
        lines.append("")

        var chapterByIndex = Dictionary(grouping: book.chapters, by: \.wordIndex).mapValues { $0.last!.title }
        var paragraphStarts = Set(book.paragraphStarts)
        var line = ""
        for (index, word) in book.words.enumerated() {
            if let chapter = chapterByIndex.removeValue(forKey: index) {
                if !line.isEmpty {
                    lines.append(line)
                    line = ""
                }
                lines.append("")
                lines.append("@chapter \(TextNormalizer.directiveText(chapter))")
            } else if paragraphStarts.remove(index) != nil, index > 0 {
                if !line.isEmpty {
                    lines.append(line)
                    line = ""
                }
                lines.append("")
                lines.append("@para")
            }

            let projected = line.isEmpty ? word.count : line.count + 1 + word.count
            if !line.isEmpty, projected > 96 {
                lines.append(line)
                line = ""
            }
            line += line.isEmpty ? word : " \(word)"
        }
        if !line.isEmpty { lines.append(line) }
        return (lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n").data(using: .utf8) ?? Data()
    }

    static func decodeText(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let win = String(data: data, encoding: .windowsCP1252) { return win }
        if let latin = String(data: data, encoding: .isoLatin1) { return latin }
        return String(decoding: data, as: UTF8.self)
    }

    private static func processRsvpLine(_ line: String, book: inout BookContent, paragraphPending: inout Bool) {
        var trimmed = stripBom(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            paragraphPending = true
            return
        }

        if trimmed.hasPrefix("@@") {
            trimmed.removeFirst()
            if paragraphPending {
                addParagraphMarker(&book)
                paragraphPending = false
            }
            book.words.append(contentsOf: TextNormalizer.cleanWords(in: trimmed))
            return
        }

        if trimmed.hasPrefix("@") {
            let lowered = trimmed.lowercased()
            if prefixHasBoundary(lowered, "@para") {
                paragraphPending = true
            } else if prefixHasBoundary(lowered, "@chapter") {
                let title = directiveValue(trimmed, "@chapter")
                addChapterMarker(&book, title: title.isEmpty ? "Chapter" : title)
                paragraphPending = true
            } else if prefixHasBoundary(lowered, "@title") {
                book.title = directiveValue(trimmed, "@title")
            } else if prefixHasBoundary(lowered, "@author") {
                book.author = directiveValue(trimmed, "@author")
            }
            return
        }

        if paragraphPending {
            addParagraphMarker(&book)
            paragraphPending = false
        }
        book.words.append(contentsOf: TextNormalizer.cleanWords(in: line))
    }

    private static func processBookLine(_ line: String, book: inout BookContent, paragraphPending: inout Bool) {
        let trimmed = stripBom(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            paragraphPending = true
            return
        }
        if let title = chapterTitle(from: line) {
            addChapterMarker(&book, title: title)
            paragraphPending = true
        }
        if paragraphPending {
            addParagraphMarker(&book)
            paragraphPending = false
        }
        book.words.append(contentsOf: TextNormalizer.cleanWords(in: line))
    }

    private static func chapterTitle(from line: String) -> String? {
        let trimmed = TextNormalizer.cleanText(stripBom(line))
        guard !trimmed.isEmpty, trimmed.count <= maxChapterTitleChars else { return nil }
        if trimmed.hasPrefix("#") {
            let title = trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : title
        }
        if trimmed.range(of: #"^(chapter|part|book)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return trimmed
        }
        return nil
    }

    private static func addChapterMarker(_ book: inout BookContent, title: String) {
        let title = TextNormalizer.cleanText(title)
        guard !title.isEmpty else { return }
        let marker = ChapterMarker(title: title, wordIndex: book.words.count)
        if let last = book.chapters.last, last.wordIndex == marker.wordIndex {
            book.chapters[book.chapters.count - 1] = marker
        } else {
            book.chapters.append(marker)
        }
    }

    private static func addParagraphMarker(_ book: inout BookContent) {
        let index = book.words.count
        if book.paragraphStarts.last != index {
            book.paragraphStarts.append(index)
        }
    }

    private static func directiveValue(_ line: String, _ directive: String) -> String {
        var value = String(line.dropFirst(directive.count)).trimmingCharacters(in: .whitespaces)
        if let first = value.first, first == ":" || first == "-" || first == "." {
            value.removeFirst()
        }
        return TextNormalizer.cleanText(value)
    }

    private static func prefixHasBoundary(_ lowered: String, _ prefix: String) -> Bool {
        guard lowered.hasPrefix(prefix) else { return false }
        if lowered.count == prefix.count { return true }
        let index = lowered.index(lowered.startIndex, offsetBy: prefix.count)
        let next = lowered[index]
        return next.isWhitespace || next == ":" || next == "." || next == "-"
    }

    private static func stripBom(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\u{feff}") {
            trimmed.removeFirst()
        }
        return trimmed
    }
}

extension BookParser {
    static func htmlEvents(_ markup: String) -> [(kind: String, value: String)] {
        var html = markup
        html = html.replacingOccurrences(of: #"(?is)<(script|style|svg|nav|head|math)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?is)<h[1-6][^>]*>(.*?)</h[1-6]>"#, with: "\n@@CHAPTER@@$1\n", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        html = html.replacingOccurrences(of: #"(?i)</(p|div|section|article|li|tr|blockquote|header|footer|figure|figcaption|td|th|ul|ol|pre)>"#, with: "\n", options: .regularExpression)
        html = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        html = TextNormalizer.escapedHtmlText(html)

        var events: [(String, String)] = []
        for raw in html.components(separatedBy: .newlines) {
            let line = TextNormalizer.cleanText(raw)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("@@CHAPTER@@") {
                let title = TextNormalizer.cleanText(String(line.dropFirst("@@CHAPTER@@".count)))
                if !title.isEmpty { events.append(("chapter", title)) }
            } else {
                events.append(("text", line))
            }
        }
        return events
    }
}

