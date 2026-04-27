import SwiftUI

@MainActor
final class ReaderViewModel: ObservableObject {
    struct ChapterRow: Identifiable, Equatable {
        let id: Int
        let title: String
        let wordIndex: Int
        let isCurrent: Bool
    }

    @Published var renderImage: UIImage
    @Published var importing = false
    @Published var chromeVisible = false
    @Published var settingsVisible = false
    @Published var actionsVisible = false
    @Published var records: [BookRecord] = []
    @Published var settings = ReaderSettings() {
        didSet { applySettings(redraw: true) }
    }

    private let renderer = RsvpRenderer()
    private let reader = ReadingLoop()
    private let store = BookStore()
    private var bookContent = BookContent()
    private var currentRecord: BookRecord?
    private var state: ReaderState = .paused
    private var timer: Timer?
    private var holdStartTimer: Timer?
    private var rewindTimer: Timer?
    private var chromeHideTimer: Timer?
    private var gestureStartIndex = 0
    private var touchActive = false
    private var touchMovedFar = false
    private var pressPlaybackActive = false
    private var rewindActive = false
    private var contextVisible = false
    private var wpmFeedbackUntil: Date?
    private var lastProgressSave = Date.distantPast
    private var renderSize: CGSize = .zero

    let typographySamples = ["minimum", "encyclopaedia", "state-of-the-art", "HTTP/2", "well-known", "rhythms", "illumination", "WAVEFORM", "I"]

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
        applySettings(redraw: false)
        redraw()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    deinit {
        timer?.invalidate()
        holdStartTimer?.invalidate()
        rewindTimer?.invalidate()
        chromeHideTimer?.invalidate()
    }

    var bookTitle: String {
        if !bookContent.title.isEmpty { return bookContent.title }
        return currentRecord?.title ?? "Demo"
    }

    var progressPercent: Int { readingProgressPercent() }
    var currentChapterTitle: String { currentChapterLabel() }
    var currentWordIndex: Int { reader.currentIndex }
    var wpm: Int { reader.wpm }
    var isPlaying: Bool { state == .playing }
    var canShowChapters: Bool { !chapterRows.isEmpty }

    var chromeSubtitle: String {
        "\(currentChapterLabel()) - \(readingProgressPercent())% - \(reader.wpm) WPM"
    }

    var chapterRows: [ChapterRow] {
        let markers = bookContent.chapters.isEmpty ? [ChapterMarker(title: "Start of book", wordIndex: 0)] : bookContent.chapters
        return markers.enumerated().map { index, marker in
            let next = markers[safe: index + 1]?.wordIndex ?? reader.wordCount
            return ChapterRow(
                id: index,
                title: marker.title,
                wordIndex: marker.wordIndex,
                isCurrent: reader.currentIndex >= marker.wordIndex && reader.currentIndex < next
            )
        }
    }

    func setViewportSize(_ viewportSize: CGSize) {
        guard viewportSize.width >= 1, viewportSize.height >= 1 else { return }
        guard abs(viewportSize.width - renderSize.width) > 0.5
           || abs(viewportSize.height - renderSize.height) > 0.5 else { return }
        renderSize = viewportSize
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
            actionsVisible = false
            settingsVisible = false
            chromeVisible = true
        } catch {
            state = .paused
            renderStatus("Import failed", line1: url.lastPathComponent, line2: error.localizedDescription)
            chromeVisible = true
        }
        importing = false
        redraw()
    }

    func toggleChrome() {
        if settingsVisible || actionsVisible {
            closePanels()
            return
        }
        chromeVisible.toggle()
        if chromeVisible { scheduleChromeAutoHideIfNeeded() }
    }

    func showChrome() {
        chromeVisible = true
        scheduleChromeAutoHideIfNeeded()
    }

    func hideChrome() {
        settingsVisible = false
        actionsVisible = false
        chromeVisible = false
        chromeHideTimer?.invalidate()
    }

    func openSettingsPanel() {
        pauseIfNeeded()
        settingsVisible = true
        actionsVisible = false
        chromeVisible = true
    }

    func openActionsPanel() {
        pauseIfNeeded()
        records = store.allRecords()
        actionsVisible = true
        settingsVisible = false
        chromeVisible = true
    }

    func closePanels() {
        settingsVisible = false
        actionsVisible = false
        chromeVisible = true
    }

    func beginImport() {
        pauseIfNeeded()
        importing = true
    }

    func selectBook(_ record: BookRecord) {
        pauseIfNeeded()
        load(record: record)
        actionsVisible = false
        chromeVisible = true
        saveProgress(force: true)
        redraw()
    }

    func selectChapter(_ row: ChapterRow) {
        pauseIfNeeded()
        reader.seekTo(row.wordIndex)
        contextVisible = false
        actionsVisible = false
        chromeVisible = true
        saveProgress(force: true)
        redraw()
    }

    func restartBook() {
        pauseIfNeeded()
        reader.seekTo(0)
        contextVisible = false
        actionsVisible = false
        chromeVisible = true
        saveProgress(force: true)
        redraw()
    }

    func resetTypography() {
        settings.typography = TypographyConfig()
    }

    func resetPacing() {
        settings.pacingLongWordLevelIndex = 2
        settings.pacingComplexWordLevelIndex = 2
        settings.pacingPunctuationLevelIndex = 2
        settings.pacingJargonLevelIndex = 2
        settings.pacingPhraseLevelIndex = 2
    }

    func touchChanged(startLocation: CGPoint, location: CGPoint, translation: CGSize) {
        if settingsVisible || actionsVisible { return }
        if !touchActive {
            touchActive = true
            touchMovedFar = false
            pressPlaybackActive = false
            rewindActive = false
            gestureStartIndex = reader.currentIndex
            scheduleHoldAction(startLocation: startLocation)
        }

        if movementDistance(translation) > 12 {
            if !touchMovedFar {
                touchMovedFar = true
                cancelHoldAction()
                stopRewindIfNeeded()
                if pressPlaybackActive { stopPressPlayback() }
            }
            dragChanged(translation)
        }
    }

    func touchEnded(startLocation: CGPoint, location: CGPoint, translation: CGSize) {
        if settingsVisible || actionsVisible {
            closePanels()
            return
        }

        let shouldHandleDrag = touchMovedFar || movementDistance(translation) > 12
        cancelHoldAction()
        if rewindActive {
            stopRewindIfNeeded()
        } else if pressPlaybackActive {
            stopPressPlayback()
        } else if shouldHandleDrag {
            dragEnded(translation)
        } else {
            toggleChrome()
        }
        touchActive = false
        touchMovedFar = false
    }

    private func applySettings(redraw shouldRedraw: Bool) {
        reader.setWpm(settings.wpm)
        reader.pacingConfig = settings.pacingConfig
        saveSettings()
        if shouldRedraw { redraw() }
    }

    private func scheduleHoldAction(startLocation: CGPoint) {
        cancelHoldAction()
        guard state == .paused else { return }
        let leftRewindEdge = max(120, renderSize.width * 0.25)
        let isLeftHold = startLocation.x <= leftRewindEdge
        holdStartTimer = Timer.scheduledTimer(withTimeInterval: isLeftHold ? 0.22 : 0.18, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if isLeftHold {
                    self?.startRewindIfNeeded()
                } else {
                    self?.startPressPlaybackIfNeeded()
                }
            }
        }
    }

    private func cancelHoldAction() {
        holdStartTimer?.invalidate()
        holdStartTimer = nil
    }

    private func startPressPlaybackIfNeeded() {
        holdStartTimer = nil
        guard touchActive, !touchMovedFar, state == .paused else { return }
        hideChrome()
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

    private func startRewindIfNeeded() {
        holdStartTimer = nil
        guard touchActive, !touchMovedFar, state == .paused else { return }
        rewindActive = true
        contextVisible = true
        showChrome()
        rewindOneWord()
        rewindTimer = Timer.scheduledTimer(withTimeInterval: rewindInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rewindOneWord() }
        }
    }

    private func rewindOneWord() {
        guard rewindActive else { return }
        if reader.stepBackward() {
            redraw()
        } else {
            stopRewindIfNeeded()
        }
    }

    private func stopRewindIfNeeded() {
        rewindTimer?.invalidate()
        rewindTimer = nil
        if rewindActive {
            rewindActive = false
            saveProgress(force: true)
            redraw()
        }
    }

    private var rewindInterval: TimeInterval {
        max(0.08, min(0.18, Double(reader.wordIntervalMs) / 1000.0))
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
        guard state == .paused else { return }
        if abs(translation.height) > abs(translation.width) + 12, abs(translation.height) > 40 {
            reader.adjustWpm(translation.height < 0 ? 1 : -1)
            settings.wpm = reader.wpm
            wpmFeedbackUntil = Date().addingTimeInterval(0.9)
            contextVisible = false
            showChrome()
        } else if abs(translation.width) > 40 {
            saveProgress(force: true)
        }
        redraw()
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

    private func pauseIfNeeded() {
        cancelHoldAction()
        stopRewindIfNeeded()
        if state == .playing {
            state = .paused
            pressPlaybackActive = false
            saveProgress(force: true)
            redraw()
        }
    }

    private func scheduleChromeAutoHideIfNeeded() {
        chromeHideTimer?.invalidate()
        guard state == .playing, !settingsVisible, !actionsVisible else { return }
        chromeHideTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .playing, !self.settingsVisible, !self.actionsVisible else { return }
                self.chromeVisible = false
            }
        }
    }

    private func redraw() {
        guard renderSize.width >= 1, renderSize.height >= 1 else { return }
        let ctx = RenderContext(
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
        renderImage = renderer.render(ctx, size: renderSize)
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

    private var nowMs: Int {
        Int(Date().timeIntervalSinceReferenceDate * 1000)
    }

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: "ReaderSettings"),
              let decoded = try? JSONDecoder().decode(ReaderSettings.self, from: data) else { return }
        settings = decoded
    }

    private func saveSettings() {
        var snapshot = settings
        snapshot.wpm = reader.wpm
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: "ReaderSettings")
        }
    }
}
