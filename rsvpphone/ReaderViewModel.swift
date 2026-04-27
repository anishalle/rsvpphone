import SwiftUI

@MainActor
final class ReaderViewModel: ObservableObject {
    enum MenuScreen {
        case main
        case settingsHome
        case settingsDisplay
        case settingsPacing
        case typography
        case library
        case chapters
        case restart
    }

    @Published var renderImage: UIImage
    @Published var importing = false

    private let renderer = RsvpRenderer()
    private let reader = ReadingLoop()
    private let store = BookStore()
    private var bookContent = BookContent()
    private var currentRecord: BookRecord?
    private var settings = ReaderSettings()
    private var state: ReaderState = .paused
    private var menuScreen: MenuScreen = .main
    private var selectedIndex = 0
    private var records: [BookRecord] = []
    private var timer: Timer?
    private var pressStartTimer: Timer?
    private var gestureStartIndex = 0
    private var touchActive = false
    private var touchMovedFar = false
    private var pressPlaybackActive = false
    private var contextVisible = false
    private var wpmFeedbackUntil: Date?
    private var lastProgressSave = Date.distantPast
    private var renderSize: CGSize = .zero

    private let menuItems = ["Resume", "Chapters", "Library", "Settings", "Restart"]
    private let settingsHome = ["Back", "Display", "Typography tune", "Word pacing"]
    private let typographySamples = ["minimum", "encyclopaedia", "state-of-the-art", "HTTP/2", "well-known", "rhythms", "illumination", "WAVEFORM", "I"]

    init() {
        renderImage = UIImage()
        loadSettings()
        records = store.allRecords()
        if let first = records.first {
            load(record: first)
        } else {
            reader.begin(nowMs: nowMs)
            bookContent = BookContent(title: "Demo", words: (0..<reader.wordCount).map { reader.wordAt($0) }, chapters: [ChapterMarker(title: "Demo", wordIndex: 0)], paragraphStarts: [0])
        }
        reader.setWpm(settings.wpm)
        reader.pacingConfig = settings.pacingConfig
        redraw()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit {
        timer?.invalidate()
        pressStartTimer?.invalidate()
    }

    func setViewportSize(_ viewportSize: CGSize) {
        let landscape = CGSize(width: max(viewportSize.width, viewportSize.height),
                               height: min(viewportSize.width, viewportSize.height))
        guard landscape.width >= 1, landscape.height >= 1 else { return }
        guard abs(landscape.width - renderSize.width) > 0.5
           || abs(landscape.height - renderSize.height) > 0.5 else { return }
        renderSize = landscape
        redraw()
    }

    func importURLs(_ urls: [URL]) {
        guard let url = urls.first else { return }
        importing = true
        do {
            let record = try store.importBook(from: url)
            records = store.allRecords()
            load(record: record)
            state = .paused
        } catch {
            state = .paused
            renderStatus("Import failed", line1: url.lastPathComponent, line2: error.localizedDescription)
        }
        importing = false
        redraw()
    }

    func openMenu() {
        guard state != .playing else { return }
        state = .menu
        menuScreen = .main
        selectedIndex = 0
        redraw()
    }

    func touchChanged(_ translation: CGSize) {
        if !touchActive {
            touchActive = true
            touchMovedFar = false
            pressPlaybackActive = false
            gestureStartIndex = reader.currentIndex
            schedulePressPlayback()
        }

        if movementDistance(translation) > 12 {
            if !touchMovedFar {
                touchMovedFar = true
                cancelPressPlayback()
                if pressPlaybackActive {
                    stopPressPlayback()
                }
            }
            dragChanged(translation)
        }
    }

    func touchEnded(_ translation: CGSize) {
        let shouldHandleDrag = touchMovedFar || movementDistance(translation) > 12
        cancelPressPlayback()
        if pressPlaybackActive {
            stopPressPlayback()
        } else if shouldHandleDrag {
            dragEnded(translation)
        } else {
            tap()
        }
        touchActive = false
        touchMovedFar = false
    }

    private func schedulePressPlayback() {
        cancelPressPlayback()
        guard state == .paused else { return }
        pressStartTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.startPressPlaybackIfNeeded()
            }
        }
    }

    private func cancelPressPlayback() {
        pressStartTimer?.invalidate()
        pressStartTimer = nil
    }

    private func startPressPlaybackIfNeeded() {
        pressStartTimer = nil
        guard touchActive, !touchMovedFar, state == .paused else { return }
        state = .playing
        pressPlaybackActive = true
        contextVisible = false
        reader.start(nowMs: nowMs)
        redraw()
    }

    private func stopPressPlayback() {
        guard state == .playing else {
            pressPlaybackActive = false
            return
        }
        state = .paused
        pressPlaybackActive = false
        saveProgress(force: true)
        redraw()
    }

    private func movementDistance(_ translation: CGSize) -> CGFloat {
        hypot(translation.width, translation.height)
    }

    private func dragChanged(_ translation: CGSize) {
        guard state == .paused else { return }
        if abs(translation.width) > abs(translation.height), abs(translation.width) > 40 {
            let steps = scrubSteps(deltaX: translation.width)
            reader.seekRelative(baseIndex: gestureStartIndex, steps: steps)
            contextVisible = true
            redraw()
        }
    }

    private func dragEnded(_ translation: CGSize) {
        if state == .menu {
            handleMenuDragEnded(translation)
            return
        }
        guard state == .paused else { return }
        if abs(translation.height) > abs(translation.width) + 12, abs(translation.height) > 40 {
            reader.adjustWpm(translation.height < 0 ? 1 : -1)
            settings.wpm = reader.wpm
            saveSettings()
            wpmFeedbackUntil = Date().addingTimeInterval(0.9)
            contextVisible = false
        } else if abs(translation.width) > 40 {
            saveProgress(force: true)
        }
        redraw()
    }

    private func tap() {
        if state == .menu {
            selectMenuItem()
        }
    }

    private func tick() {
        if state == .playing, reader.update(nowMs: nowMs) {
            redraw()
        }
        if state == .playing, Date().timeIntervalSince(lastProgressSave) > 15 {
            saveProgress(force: false)
        }
        if let until = wpmFeedbackUntil, Date() >= until {
            wpmFeedbackUntil = nil
            redraw()
        }
    }

    private func handleMenuDragEnded(_ translation: CGSize) {
        if abs(translation.height) > abs(translation.width) + 12, abs(translation.height) > 40 {
            moveSelection(translation.height < 0 ? -1 : 1)
        } else if abs(translation.width) > 40, menuScreen == .typography {
            moveSelection(translation.width < 0 ? 1 : -1)
        } else if abs(translation.width) < 18, abs(translation.height) < 18 {
            selectMenuItem()
        }
    }

    private func moveSelection(_ delta: Int) {
        let count = currentMenuCount()
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
        redraw()
    }

    private func selectMenuItem() {
        switch menuScreen {
        case .main:
            switch selectedIndex {
            case 0: state = .paused
            case 1: menuScreen = .chapters; selectedIndex = currentChapterSelection()
            case 2: records = store.allRecords(); menuScreen = .library; selectedIndex = 0
            case 3: menuScreen = .settingsHome; selectedIndex = 1
            case 4: reader.seekTo(0); state = .paused; saveProgress(force: true)
            default: break
            }
        case .settingsHome:
            if selectedIndex == 0 { menuScreen = .main; selectedIndex = 0 }
            else if selectedIndex == 1 { menuScreen = .settingsDisplay; selectedIndex = 1 }
            else if selectedIndex == 2 { menuScreen = .typography; selectedIndex = 1 }
            else if selectedIndex == 3 { menuScreen = .settingsPacing; selectedIndex = 1 }
        case .settingsDisplay:
            handleDisplaySettings()
        case .settingsPacing:
            handlePacingSettings()
        case .typography:
            handleTypography()
        case .library:
            if selectedIndex == 0 {
                importing = true
            } else if selectedIndex - 1 < records.count {
                load(record: records[selectedIndex - 1])
                state = .paused
            }
        case .chapters:
            if selectedIndex == 0 { menuScreen = .main; selectedIndex = 0 }
            else {
                let idx = selectedIndex - 1
                let chapter = bookContent.chapters[safe: idx] ?? ChapterMarker(title: "Start", wordIndex: 0)
                reader.seekTo(chapter.wordIndex)
                state = .paused
                saveProgress(force: true)
            }
        case .restart:
            state = .paused
        }
        saveSettings()
        redraw()
    }

    private func handleDisplaySettings() {
        if selectedIndex == 0 { menuScreen = .settingsHome; selectedIndex = 1; return }
        if selectedIndex == 1 {
            let modes = ThemeMode.allCases
            settings.theme = modes[(settings.theme.rawValue + 1) % modes.count]
        } else if selectedIndex == 2 {
            settings.brightnessLevelIndex = (settings.brightnessLevelIndex + 1) % ReaderSettings.brightnessLevels.count
        } else if selectedIndex == 3 {
            settings.phantomWordsEnabled.toggle()
        } else if selectedIndex == 4 {
            settings.fontSizeLevel = (settings.fontSizeLevel + 1) % ReaderSettings.readerFontSizeLabels.count
        } else if selectedIndex == 5 {
            menuScreen = .typography
            selectedIndex = 1
        }
    }

    private func handlePacingSettings() {
        if selectedIndex == 0 { menuScreen = .settingsHome; selectedIndex = 3; return }
        if selectedIndex == 1 { settings.pacingLongWordLevelIndex = (settings.pacingLongWordLevelIndex + 1) % ReaderSettings.pacingScaleLabels.count }
        else if selectedIndex == 2 { settings.pacingComplexWordLevelIndex = (settings.pacingComplexWordLevelIndex + 1) % ReaderSettings.pacingScaleLabels.count }
        else if selectedIndex == 3 { settings.pacingPunctuationLevelIndex = (settings.pacingPunctuationLevelIndex + 1) % ReaderSettings.pacingScaleLabels.count }
        else if selectedIndex == 4 {
            settings.pacingLongWordLevelIndex = 2
            settings.pacingComplexWordLevelIndex = 2
            settings.pacingPunctuationLevelIndex = 2
        }
        reader.pacingConfig = settings.pacingConfig
    }

    private func handleTypography() {
        if selectedIndex == 0 { menuScreen = .settingsHome; selectedIndex = 2; return }
        if selectedIndex == 1 { settings.typography.trackingPx = next(settings.typography.trackingPx, min: -2, max: 3) }
        else if selectedIndex == 2 { settings.typography.anchorPercent = next(settings.typography.anchorPercent, min: 30, max: 40) }
        else if selectedIndex == 3 { settings.typography.guideHalfWidth = next(settings.typography.guideHalfWidth, min: 12, max: 30, step: 2) }
        else if selectedIndex == 4 { settings.typography.guideGap = next(settings.typography.guideGap, min: 2, max: 8) }
        else if selectedIndex == 5 { settings.typography = TypographyConfig() }
    }

    private func currentMenuCount() -> Int {
        switch menuScreen {
        case .main: return menuItems.count
        case .settingsHome: return settingsHome.count
        case .settingsDisplay: return displaySettingsItems().count
        case .settingsPacing: return pacingSettingsItems().count
        case .typography: return typographyItems().count
        case .library: return records.count + 1
        case .chapters: return max(2, bookContent.chapters.count + 1)
        case .restart: return 2
        }
    }

    private func redraw() {
        guard renderSize.width >= 1, renderSize.height >= 1 else { return }
        let ctx: RenderContext
        if state == .menu {
            ctx = menuRenderContext()
        } else {
            ctx = RenderContext(
                state: state,
                word: reader.currentWord,
                beforeText: settings.phantomWordsEnabled ? phantomBeforeText() : "",
                afterText: settings.phantomWordsEnabled ? phantomAfterText() : "",
                chapterLabel: currentChapterLabel(),
                progressPercent: readingProgressPercent(),
                settings: settings,
                showFooter: state != .playing,
                wpmFeedback: wpmFeedbackUntil == nil ? nil : reader.wpm,
                contextWords: contextVisible ? contextWords() : []
            )
        }
        renderImage = renderer.render(ctx, size: renderSize)
    }

    private func menuRenderContext() -> RenderContext {
        var context = RenderContext(state: state, word: reader.currentWord, beforeText: "", afterText: "", chapterLabel: currentChapterLabel(), progressPercent: readingProgressPercent(), settings: settings, showFooter: true)
        context.selectedIndex = selectedIndex
        switch menuScreen {
        case .main: context.menuItems = menuItems
        case .settingsHome: context.menuItems = settingsHome
        case .settingsDisplay: context.menuItems = displaySettingsItems()
        case .settingsPacing: context.menuItems = pacingSettingsItems()
        case .typography: context.menuItems = typographyItems()
        case .library:
            context.libraryItems = [RsvpRenderer.LibraryItem(title: "Import", subtitle: "Files app")] + records.map {
                let percent = $0.wordCount > 1 ? "\(($0.currentWordIndex * 100) / max(1, $0.wordCount - 1))%" : ""
                return RsvpRenderer.LibraryItem(title: $0.title, subtitle: [$0.author, percent].filter { !$0.isEmpty }.joined(separator: " - "))
            }
        case .chapters:
            context.menuItems = ["Back"] + (bookContent.chapters.isEmpty ? ["Start of book"] : bookContent.chapters.enumerated().map { "\($0.offset + 1) \($0.element.title)" })
        case .restart:
            context.menuItems = ["No, keep place", "Yes, restart"]
        }
        return context
    }

    private func displaySettingsItems() -> [String] {
        ["Back", "Theme: \(settings.theme.label)", "Brightness: \(settings.brightnessPercent)%", "Phantom words: \(settings.phantomWordsEnabled ? "On" : "Off")", "Font size: \(ReaderSettings.readerFontSizeLabels[safe: settings.fontSizeLevel] ?? "Large")", "Typography tune"]
    }

    private func pacingSettingsItems() -> [String] {
        ["Back", "Long words: \(ReaderSettings.pacingScaleLabels[settings.pacingLongWordLevelIndex])", "Complexity: \(ReaderSettings.pacingScaleLabels[settings.pacingComplexWordLevelIndex])", "Punctuation: \(ReaderSettings.pacingScaleLabels[settings.pacingPunctuationLevelIndex])", "Reset pacing"]
    }

    private func typographyItems() -> [String] {
        ["Back", "Tracking: \(settings.typography.trackingPx >= 0 ? "+" : "")\(settings.typography.trackingPx) px", "Anchor: \(settings.typography.anchorPercent)%", "Guide width: \(settings.typography.guideHalfWidth) px", "Guide gap: \(settings.typography.guideGap) px", "Reset"]
    }

    private func load(record: BookRecord) {
        do {
            let content = try store.content(for: record)
            bookContent = content
            currentRecord = record
            reader.setWords(content.words, nowMs: nowMs)
            reader.seekTo(record.currentWordIndex)
        } catch {
            renderStatus("Book failed", line1: record.title, line2: error.localizedDescription)
        }
    }

    private func renderStatus(_ title: String, line1: String, line2: String) {
        let size = renderSize.width >= 1 ? renderSize : RsvpRenderer.logicalSize
        renderImage = renderer.render(RenderContext(state: .paused, word: "", beforeText: "", afterText: "", chapterLabel: "", progressPercent: 0, settings: settings, showFooter: false, statusTitle: title, statusLine1: line1, statusLine2: line2), size: size)
    }

    private func saveProgress(force: Bool) {
        guard let record = currentRecord else { return }
        if !force, reader.currentIndex == record.currentWordIndex { return }
        store.updateProgress(path: record.path, wordIndex: reader.currentIndex, wordCount: reader.wordCount)
        records = store.allRecords()
        currentRecord = records.first { $0.path == record.path }
        lastProgressSave = Date()
    }

    private func currentChapterLabel() -> String {
        guard !bookContent.chapters.isEmpty else { return bookContent.title.isEmpty ? "Start" : bookContent.title }
        var current = bookContent.chapters[0]
        for marker in bookContent.chapters where marker.wordIndex <= reader.currentIndex {
            current = marker
        }
        return current.title
    }

    private func currentChapterSelection() -> Int {
        guard !bookContent.chapters.isEmpty else { return 1 }
        var selected = 0
        for (idx, marker) in bookContent.chapters.enumerated() where marker.wordIndex <= reader.currentIndex {
            selected = idx
        }
        return selected + 1
    }

    private func readingProgressPercent() -> Int {
        guard reader.wordCount > 1 else { return 0 }
        return min(100, (reader.currentIndex * 100) / (reader.wordCount - 1))
    }

    private func phantomBeforeText() -> String {
        collectWords(start: max(0, reader.currentIndex - 48), end: reader.currentIndex, target: [64, 96, 144][safe: settings.fontSizeLevel] ?? 64)
    }

    private func phantomAfterText() -> String {
        collectWords(start: reader.currentIndex + 1, end: min(reader.wordCount, reader.currentIndex + 64), target: [96, 144, 208][safe: settings.fontSizeLevel] ?? 96)
    }

    private func collectWords(start: Int, end: Int, target: Int) -> String {
        guard start < end else { return "" }
        var words: [String] = []
        var total = 0
        let range = start < reader.currentIndex ? Array(start..<end).reversed() : Array(start..<end)
        for idx in range {
            let word = reader.wordAt(idx)
            words.append(word)
            total += word.count + (words.count > 1 ? 1 : 0)
            if total >= target { break }
        }
        if start < reader.currentIndex { words.reverse() }
        return words.joined(separator: " ")
    }

    private func contextWords() -> [RsvpRenderer.ContextWord] {
        let start = max(0, reader.currentIndex - 112)
        let end = min(reader.wordCount, start + 288)
        let paragraphs = Set(bookContent.paragraphStarts)
        return (start..<end).map {
            RsvpRenderer.ContextWord(text: reader.wordAt($0), paragraphStart: $0 == 0 || paragraphs.contains($0), current: $0 == reader.currentIndex)
        }
    }

    private func scrubSteps(deltaX: CGFloat) -> Int {
        let absX = abs(deltaX)
        guard absX >= 40 else { return 0 }
        let steps = min(96, 1 + Int((absX - 40) / 22))
        return deltaX > 0 ? steps : -steps
    }

    private func next(_ value: Int, min: Int, max: Int, step: Int = 1) -> Int {
        let normalized = Swift.max(min, Swift.min(max, value))
        let candidate = normalized + step
        return candidate > max ? min : candidate
    }

    private var nowMs: Int {
        Int(Date().timeIntervalSinceReferenceDate * 1000)
    }

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: "ReaderSettings"),
              let decoded = try? JSONDecoder().decode(ReaderSettings.self, from: data) else { return }
        settings = decoded
    }

    private func saveSettings() {
        settings.wpm = reader.wpm
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "ReaderSettings")
        }
    }
}
