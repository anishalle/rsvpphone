import XCTest
@testable import rsvpphone

final class BookParserTests: XCTestCase {
    func testRsvpDirectivesAndParagraphs() {
        let text = """
        @rsvp 1
        @title The Book Title
        @author Author Name
        @chapter Chapter 1
        This is a line.
        @para
        Another paragraph.
        """
        let book = BookParser.parseRsvp(text)
        XCTAssertEqual(book.title, "The Book Title")
        XCTAssertEqual(book.author, "Author Name")
        XCTAssertEqual(book.chapters, [ChapterMarker(title: "Chapter 1", wordIndex: 0)])
        XCTAssertEqual(book.paragraphStarts, [0, 5])
        XCTAssertEqual(Array(book.words.prefix(4)), ["This", "is", "a", "line."])
    }

    func testPlainChapterDetectionAndNormalization() {
        let book = BookParser.parsePlain("""
        Chapter 1
        “Café” — naïve… test

        Part Two
        ffi ﬂ
        """, fallbackTitle: "sample")
        XCTAssertEqual(book.title, "sample")
        XCTAssertEqual(book.chapters.map(\.title), ["Chapter 1", "Part Two"])
        XCTAssertTrue(book.words.contains("Cafe"))
        XCTAssertTrue(book.words.contains("naive..."))
        XCTAssertTrue(book.words.contains("ffi"))
        XCTAssertTrue(book.words.contains("fl"))
    }

    func testHtmlExtraction() {
        let events = BookParser.htmlEvents("<html><body><h1>Intro</h1><p>Hello <b>reader</b>.</p><script>no</script></body></html>")
        XCTAssertEqual(events.first?.kind, "chapter")
        XCTAssertEqual(events.first?.value, "Intro")
        XCTAssertTrue(events.contains { $0.kind == "text" && $0.value == "Hello reader." })
    }
}
