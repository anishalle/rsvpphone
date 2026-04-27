import XCTest
@testable import rsvpphone

@MainActor
final class ReaderViewModelInteractionTests: XCTestCase {
    func testTapTogglesChromeWithoutMovingPosition() {
        let model = ReaderViewModel()
        model.setViewportSize(CGSize(width: 800, height: 390))
        let start = CGPoint(x: 400, y: 180)
        let initialIndex = model.currentWordIndex

        model.touchChanged(startLocation: start, location: start, translation: .zero)
        model.touchEnded(startLocation: start, location: start, translation: .zero)

        XCTAssertTrue(model.chromeVisible)
        XCTAssertEqual(model.currentWordIndex, initialIndex)
    }

    func testCenterHoldPlaysUntilRelease() async throws {
        let model = ReaderViewModel()
        model.setViewportSize(CGSize(width: 800, height: 390))
        let start = CGPoint(x: 420, y: 180)

        model.touchChanged(startLocation: start, location: start, translation: .zero)
        try await Task.sleep(nanoseconds: 260_000_000)

        XCTAssertTrue(model.isPlaying)

        model.touchEnded(startLocation: start, location: start, translation: .zero)

        XCTAssertFalse(model.isPlaying)
    }

    func testLeftHoldRewindsContinuouslyAndClamps() async throws {
        let model = ReaderViewModel()
        model.setViewportSize(CGSize(width: 800, height: 390))
        let dragStart = CGPoint(x: 430, y: 180)

        model.touchChanged(startLocation: dragStart, location: CGPoint(x: 520, y: 180), translation: CGSize(width: 90, height: 0))
        model.touchEnded(startLocation: dragStart, location: CGPoint(x: 520, y: 180), translation: CGSize(width: 90, height: 0))
        XCTAssertGreaterThan(model.currentWordIndex, 0)

        let advancedIndex = model.currentWordIndex
        let holdStart = CGPoint(x: 40, y: 180)
        model.touchChanged(startLocation: holdStart, location: holdStart, translation: .zero)
        try await Task.sleep(nanoseconds: 390_000_000)
        model.touchEnded(startLocation: holdStart, location: holdStart, translation: .zero)

        XCTAssertLessThan(model.currentWordIndex, advancedIndex)
        XCTAssertGreaterThanOrEqual(model.currentWordIndex, 0)
    }

    func testDragGesturesStillScrubAndAdjustWpm() {
        let model = ReaderViewModel()
        model.setViewportSize(CGSize(width: 800, height: 390))
        let start = CGPoint(x: 430, y: 180)

        model.touchChanged(startLocation: start, location: CGPoint(x: 520, y: 180), translation: CGSize(width: 90, height: 0))
        model.touchEnded(startLocation: start, location: CGPoint(x: 520, y: 180), translation: CGSize(width: 90, height: 0))
        XCTAssertGreaterThan(model.currentWordIndex, 0)

        let initialWpm = model.wpm
        model.touchChanged(startLocation: start, location: CGPoint(x: 430, y: 100), translation: CGSize(width: 0, height: -80))
        model.touchEnded(startLocation: start, location: CGPoint(x: 430, y: 100), translation: CGSize(width: 0, height: -80))
        XCTAssertGreaterThan(model.wpm, initialWpm)
    }
}
