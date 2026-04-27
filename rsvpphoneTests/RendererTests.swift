import XCTest
@testable import rsvpphone

final class RendererTests: XCTestCase {
    func testFocusLetterOrdinal() {
        let renderer = RsvpRenderer()
        XCTAssertEqual(renderer.focusLetterIndex("I"), 0)
        XCTAssertEqual(renderer.focusLetterIndex("hello"), 1)
        XCTAssertEqual(renderer.focusLetterIndex("strength"), 2)
        XCTAssertEqual(renderer.focusLetterIndex("encyclopaedia"), 3)
    }

    func testRendererProducesLogicalImage() {
        let renderer = RsvpRenderer()
        let image = renderer.render(renderContext())
        XCTAssertEqual(image.size.width, 640)
        XCTAssertEqual(image.size.height, 172)
        XCTAssertGreaterThan(nonBackgroundPixelCount(image), 100)
    }

    func testRendererProducesViewportSizedImage() {
        let renderer = RsvpRenderer()
        let viewportSize = CGSize(width: 844, height: 390)
        let image = renderer.render(renderContext(), size: viewportSize)
        XCTAssertEqual(image.size.width, viewportSize.width)
        XCTAssertEqual(image.size.height, viewportSize.height)
        XCTAssertGreaterThan(nonBackgroundPixelCount(image), 100)
    }

    private func renderContext() -> RenderContext {
        RenderContext(
            state: .paused,
            word: "reading",
            beforeText: "fast",
            afterText: "is fun",
            chapterLabel: "Start",
            progressPercent: 12,
            settings: ReaderSettings(),
            showFooter: true
        )
    }

    private func nonBackgroundPixelCount(_ image: UIImage) -> Int {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        var count = 0
        let length = CFDataGetLength(data)
        var index = 0
        while index + 3 < length {
            if bytes[index] != 0 || bytes[index + 1] != 0 || bytes[index + 2] != 0 {
                count += 1
            }
            index += 4
        }
        return count
    }
}
