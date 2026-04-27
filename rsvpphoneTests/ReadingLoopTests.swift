import XCTest
@testable import rsvpphone

final class ReadingLoopTests: XCTestCase {
    private func reader(_ wpm: Int = 300, _ words: [String]) -> ReadingLoop {
        let loop = ReadingLoop()
        loop.setWpm(wpm)
        loop.setWords(words, nowMs: 0)
        return loop
    }

    private func duration(_ word: String, _ next: String = "the") -> Int {
        reader(300, ["\(word)", "\(next)"]).currentWordDurationMs()
    }

    func testWpmBaseInterval() {
        let loop = ReadingLoop()
        loop.setWpm(300)
        XCTAssertEqual(loop.wordIntervalMs, 200)
        loop.setWpm(600)
        XCTAssertEqual(loop.wordIntervalMs, 100)
    }

    func testWpmClampsAndSteps() {
        let loop = ReadingLoop()
        loop.setWpm(50)
        XCTAssertEqual(loop.wpm, 100)
        loop.setWpm(9999)
        XCTAssertEqual(loop.wpm, 1000)
        loop.setWpm(300)
        loop.adjustWpm(1)
        XCTAssertEqual(loop.wpm, 325)
        loop.adjustWpm(-1)
        XCTAssertEqual(loop.wpm, 300)
    }

    func testShortWordNoBonus() {
        XCTAssertEqual(duration("a", "b"), 200)
    }

    func testPunctuationPauses() {
        XCTAssertEqual(duration("hi,", "there"), 290)
        XCTAssertEqual(duration("done.", "The"), 470)
        XCTAssertEqual(duration("yes!", "The"), 500)
        XCTAssertEqual(duration("thus;", "the"), 360)
        XCTAssertEqual(duration("so-", "the"), 320)
        XCTAssertEqual(duration("and...", "then"), 420)
    }

    func testAbbreviationSuppression() {
        XCTAssertEqual(duration("Mr.", "Smith"), 200)
        XCTAssertEqual(duration("U.S.", "The"), 244)
        XCTAssertEqual(duration("it.", "was"), 200)
        XCTAssertEqual(duration("chapter.", "The"), 482)
    }

    func testLengthAndComplexityBonuses() {
        XCTAssertEqual(duration("strength", "and"), 224)
        XCTAssertEqual(duration("information", "is"), 318)
        XCTAssertEqual(duration("well-known", "and"), 264)
        XCTAssertEqual(duration("NASA", "sent"), 228)
    }

    func testPacingScale() {
        let punctuation = reader(300, ["done.", "The"])
        punctuation.pacingConfig = PacingConfig(longWordScalePercent: 100, complexWordScalePercent: 100, punctuationScalePercent: 50)
        XCTAssertEqual(punctuation.currentWordDurationMs(), 334)

        let length = reader(300, ["strength", "and"])
        length.pacingConfig = PacingConfig(longWordScalePercent: 0, complexWordScalePercent: 100, punctuationScalePercent: 100)
        XCTAssertEqual(length.currentWordDurationMs(), 206)
    }

    func testJargonScaleIsIndependentFromComplexity() {
        let loop = reader(300, ["HTTP/2", "request"])
        loop.pacingConfig = PacingConfig(
            longWordScalePercent: 100,
            complexWordScalePercent: 0,
            punctuationScalePercent: 100,
            jargonScalePercent: 0,
            phraseScalePercent: 100
        )
        let withoutJargon = loop.currentWordDurationMs()

        loop.pacingConfig = PacingConfig(
            longWordScalePercent: 100,
            complexWordScalePercent: 0,
            punctuationScalePercent: 100,
            jargonScalePercent: 150,
            phraseScalePercent: 100
        )
        XCTAssertGreaterThan(loop.currentWordDurationMs(), withoutJargon)
    }

    func testPhraseScaleIsIndependentFromSentencePunctuation() {
        let phrase = reader(300, ["however,", "the"])
        phrase.pacingConfig = PacingConfig(
            longWordScalePercent: 100,
            complexWordScalePercent: 100,
            punctuationScalePercent: 0,
            jargonScalePercent: 100,
            phraseScalePercent: 0
        )
        let withoutPhrasePause = phrase.currentWordDurationMs()

        phrase.pacingConfig = PacingConfig(
            longWordScalePercent: 100,
            complexWordScalePercent: 100,
            punctuationScalePercent: 0,
            jargonScalePercent: 100,
            phraseScalePercent: 150
        )
        XCTAssertGreaterThan(phrase.currentWordDurationMs(), withoutPhrasePause)

        let sentence = reader(300, ["done.", "The"])
        sentence.pacingConfig = PacingConfig(
            longWordScalePercent: 100,
            complexWordScalePercent: 100,
            punctuationScalePercent: 100,
            jargonScalePercent: 100,
            phraseScalePercent: 0
        )
        XCTAssertEqual(sentence.currentWordDurationMs(), 470)
    }

    func testSeekAndScrubClampLoadedBook() {
        let loop = reader(300, ["one", "two", "three"])
        loop.seekRelative(baseIndex: 0, steps: -10)
        XCTAssertEqual(loop.currentIndex, 0)
        loop.seekRelative(baseIndex: 0, steps: 10)
        XCTAssertEqual(loop.currentIndex, 2)
    }

    func testStepBackwardClampsLoadedBook() {
        let loop = reader(300, ["one", "two", "three"])
        loop.seekTo(2)
        XCTAssertTrue(loop.stepBackward())
        XCTAssertEqual(loop.currentIndex, 1)
        XCTAssertTrue(loop.stepBackward())
        XCTAssertEqual(loop.currentIndex, 0)
        XCTAssertFalse(loop.stepBackward())
        XCTAssertEqual(loop.currentIndex, 0)
    }
}
