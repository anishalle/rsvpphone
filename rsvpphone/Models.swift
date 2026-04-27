import Foundation
import UniformTypeIdentifiers

struct ChapterMarker: Codable, Equatable {
    var title: String
    var wordIndex: Int
}

struct BookContent: Equatable {
    var title: String = ""
    var author: String = ""
    var words: [String] = []
    var chapters: [ChapterMarker] = []
    var paragraphStarts: [Int] = []
}

enum ReaderState: String, Codable {
    case booting
    case paused
    case playing
    case menu
    case importing
}

enum ThemeMode: Int, Codable, CaseIterable {
    case dark
    case light
    case night

    var label: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .night: return "Night"
        }
    }
}

struct TypographyConfig: Codable, Equatable {
    var trackingPx: Int = 0
    var anchorPercent: Int = 35
    var guideHalfWidth: Int = 20
    var guideGap: Int = 4
}

struct PacingConfig: Codable, Equatable {
    var longWordScalePercent: Int = 100
    var complexWordScalePercent: Int = 100
    var punctuationScalePercent: Int = 100
}

struct ReaderSettings: Codable, Equatable {
    var wpm: Int = 300
    var theme: ThemeMode = .dark
    var phantomWordsEnabled: Bool = true
    var fontSizeLevel: Int = 0
    var brightnessLevelIndex: Int = 4
    var pacingLongWordLevelIndex: Int = 2
    var pacingComplexWordLevelIndex: Int = 2
    var pacingPunctuationLevelIndex: Int = 2
    var typography = TypographyConfig()

    static let pacingScalePercents = [60, 80, 100, 125, 150]
    static let pacingScaleLabels = ["VLow", "Low", "Bal", "High", "Max"]
    static let readerFontSizeLabels = ["Large", "Medium", "Small"]
    static let brightnessLevels = [40, 55, 70, 85, 100]
    static let nightBrightnessLevels = [35, 40, 45, 50, 55]

    var pacingConfig: PacingConfig {
        PacingConfig(
            longWordScalePercent: Self.pacingScalePercents[safe: pacingLongWordLevelIndex] ?? 100,
            complexWordScalePercent: Self.pacingScalePercents[safe: pacingComplexWordLevelIndex] ?? 100,
            punctuationScalePercent: Self.pacingScalePercents[safe: pacingPunctuationLevelIndex] ?? 100
        )
    }

    var brightnessPercent: Int {
        let levels = theme == .night ? Self.nightBrightnessLevels : Self.brightnessLevels
        return levels[safe: brightnessLevelIndex] ?? levels.last ?? 100
    }
}

struct BookRecord: Codable, Equatable, Identifiable {
    var id: String { path.lastPathComponent }
    var path: URL
    var title: String
    var author: String
    var wordCount: Int
    var currentWordIndex: Int
    var recentSequence: Int
}

struct RenderContext {
    var state: ReaderState
    var word: String
    var beforeText: String
    var afterText: String
    var chapterLabel: String
    var progressPercent: Int
    var settings: ReaderSettings
    var showFooter: Bool
    var wpmFeedback: Int?
    var contextWords: [RsvpRenderer.ContextWord] = []
    var menuItems: [String] = []
    var libraryItems: [RsvpRenderer.LibraryItem] = []
    var selectedIndex: Int = 0
    var statusTitle: String?
    var statusLine1: String = ""
    var statusLine2: String = ""
    var progressValue: Int?
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

extension UTType {
    static let rsvp = UTType(exportedAs: "com.anishalle.rsvp", conformingTo: .plainText)
    static let epub = UTType(filenameExtension: "epub") ?? UTType(exportedAs: "org.idpf.epub-container")
    static let markdownBook = UTType(filenameExtension: "md") ?? .plainText
}

