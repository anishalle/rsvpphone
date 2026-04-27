import Foundation

final class ReadingLoop {
    private static let demoWords = [
        "This", "is", "the", "minimal", "RSVP", "demo", "reader", "running", "on",
        "the", "Waveshare", "AMOLED", "board", "with", "one", "word", "at", "a", "time."
    ]

    private let minWpm = 100
    private let maxWpm = 1000
    private let wpmStep = 25
    private let maxCatchUpWords = 4

    private(set) var currentIndex = 0
    private(set) var lastAdvanceMs = 0
    private(set) var wpm = 300
    private(set) var currentWord = ""
    private var loadedWords: [String] = []
    var pacingConfig = PacingConfig()

    var wordCount: Int { loadedWords.isEmpty ? Self.demoWords.count : loadedWords.count }
    var wordIntervalMs: Int { 60_000 / max(1, wpm) }

    func begin(nowMs: Int) {
        currentIndex = 0
        lastAdvanceMs = nowMs
        setCurrentWordFromIndex()
    }

    func setWords(_ words: [String], nowMs: Int) {
        loadedWords = words
        currentIndex = 0
        lastAdvanceMs = nowMs
        setCurrentWordFromIndex()
    }

    func start(nowMs: Int) {
        lastAdvanceMs = nowMs
    }

    @discardableResult
    func update(nowMs: Int) -> Bool {
        var changed = false
        for _ in 0..<maxCatchUpWords {
            let duration = currentWordDurationMs()
            guard duration > 0, nowMs - lastAdvanceMs >= duration else { break }
            lastAdvanceMs += duration
            guard advance(1) else { break }
            changed = true
        }
        return changed
    }

    func currentWordDurationMs() -> Int {
        guard !currentWord.isEmpty else { return wordIntervalMs }
        let nextIndex = currentIndex + 1
        let nextStartsLower = nextIndex < wordCount ? Self.startsWithLowercaseLetter(wordAt(nextIndex)) : false
        return Self.durationForWord(currentWord, nextWordStartsLowercase: nextStartsLower, baseIntervalMs: wordIntervalMs, config: pacingConfig)
    }

    func wordAt(_ index: Int) -> String {
        if !loadedWords.isEmpty { return loadedWords[index] }
        return Self.demoWords[index]
    }

    func scrub(_ steps: Int) {
        seekRelative(baseIndex: currentIndex, steps: steps)
    }

    func seekTo(_ wordIndex: Int) {
        guard wordCount > 0 else {
            currentWord = ""
            return
        }
        currentIndex = min(max(0, wordIndex), wordCount - 1)
        setCurrentWordFromIndex()
    }

    func seekRelative(baseIndex: Int, steps: Int) {
        guard wordCount > 0 else { return }
        let base = min(max(0, baseIndex), wordCount - 1)
        var next = base + steps
        if !loadedWords.isEmpty {
            next = min(max(0, next), wordCount - 1)
        } else {
            next %= wordCount
            if next < 0 { next += wordCount }
        }
        currentIndex = next
        setCurrentWordFromIndex()
    }

    func adjustWpm(_ delta: Int) {
        guard delta != 0 else { return }
        setWpm(wpm + (delta > 0 ? wpmStep : -wpmStep))
    }

    func setWpm(_ next: Int) {
        wpm = min(maxWpm, max(minWpm, next))
    }

    private func advance(_ steps: Int) -> Bool {
        guard wordCount > 0 else {
            currentWord = ""
            return false
        }
        let previous = currentIndex
        if !loadedWords.isEmpty {
            currentIndex = min(wordCount - 1, currentIndex + steps)
        } else {
            currentIndex = (currentIndex + steps) % wordCount
        }
        guard currentIndex != previous else { return false }
        setCurrentWordFromIndex()
        return true
    }

    private func setCurrentWordFromIndex() {
        currentWord = wordCount == 0 ? "" : wordAt(currentIndex)
    }
}

extension ReadingLoop {
    private static func isWordCharacter(_ ch: Character) -> Bool { ch.isLetter || ch.isNumber }
    private static func isLetterCharacter(_ ch: Character) -> Bool { ch.isLetter }
    private static func isDigitCharacter(_ ch: Character) -> Bool { ch.isNumber }
    private static func isLowercaseLetter(_ ch: Character) -> Bool { String(ch).rangeOfCharacter(from: .lowercaseLetters) != nil }
    private static func isUppercaseLetter(_ ch: Character) -> Bool { String(ch).rangeOfCharacter(from: .uppercaseLetters) != nil }
    private static func isVowelCharacter(_ ch: Character) -> Bool { "aeiouy".contains(String(ch).lowercased()) }
    private static func isSegmentSeparator(_ ch: Character) -> Bool { ch == "-" || ch == "/" || ch == "_" }
    private static func isTechnicalConnector(_ ch: Character) -> Bool { "-/_.+\\".contains(ch) }
    private static func isIgnoredTrailingChar(_ ch: Character) -> Bool { "\"')]}".contains(ch) }

    private static func chars(_ word: String) -> [Character] { Array(word) }
    private static func letterCharacterCount(_ word: String) -> Int { word.filter(isLetterCharacter).count }
    private static func digitCharacterCount(_ word: String) -> Int { word.filter(isDigitCharacter).count }
    private static func uppercaseLetterCount(_ word: String) -> Int { word.filter(isUppercaseLetter).count }
    private static func readableCharacterCount(_ word: String) -> Int { word.filter(isWordCharacter).count }

    private static func approximateSyllableGroupCount(_ word: String) -> Int {
        var groups = 0
        var letterCount = 0
        var previousWasVowel = false
        var lettersOnly = ""
        for c in chars(word) {
            guard isLetterCharacter(c) else {
                previousWasVowel = false
                continue
            }
            letterCount += 1
            let lowered = Character(String(c).lowercased())
            lettersOnly.append(lowered)
            let vowel = isVowelCharacter(lowered)
            if vowel && !previousWasVowel { groups += 1 }
            previousWasVowel = vowel
        }
        if groups > 1, letterCount > 3, lettersOnly.hasSuffix("e"), !lettersOnly.hasSuffix("le"), !lettersOnly.hasSuffix("ye") {
            groups -= 1
        }
        if groups == 0, letterCount > 0 { groups = 1 }
        return groups
    }

    private static func connectorCount(_ word: String, predicate: (Character) -> Bool) -> Int {
        let c = chars(word)
        guard c.count >= 3 else { return 0 }
        var count = 0
        for i in 1..<(c.count - 1) where predicate(c[i]) && isWordCharacter(c[i - 1]) && isWordCharacter(c[i + 1]) {
            count += 1
        }
        return count
    }

    private static func lastMeaningfulCharIndex(_ word: String) -> Int {
        let c = chars(word)
        for i in stride(from: c.count - 1, through: 0, by: -1) where !isIgnoredTrailingChar(c[i]) {
            return i
        }
        return -1
    }

    private static func trailingRhythmChar(_ word: String) -> Character? {
        let index = lastMeaningfulCharIndex(word)
        guard index >= 0 else { return nil }
        return chars(word)[index]
    }

    private static func trailingRepeatedCharCount(_ word: String, target: Character) -> Int {
        let c = chars(word)
        var count = 0
        let last = lastMeaningfulCharIndex(word)
        guard last >= 0 else { return 0 }
        for i in stride(from: last, through: 0, by: -1) {
            guard c[i] == target else { break }
            count += 1
        }
        return count
    }

    private static func startsWithLowercaseLetter(_ word: String) -> Bool {
        for c in chars(word) {
            if isLowercaseLetter(c) { return true }
            if isLetterCharacter(c) { return false }
        }
        return false
    }

    private static func isDottedInitialism(_ word: String) -> Bool {
        let c = chars(word)
        let end = lastMeaningfulCharIndex(word)
        guard end > 0 else { return false }
        var letterCount = 0
        var expectLetter = true
        for i in 0...end {
            if expectLetter {
                guard isLetterCharacter(c[i]) else { return false }
                letterCount += 1
                expectLetter = false
            } else if c[i] == "." {
                expectLetter = true
            } else {
                return false
            }
        }
        return expectLetter && letterCount >= 2
    }

    private static func looksLikeAbbreviation(_ word: String, nextWordStartsLowercase: Bool) -> Bool {
        let lowered = word.lowercased()
        let known = ["mr.", "mrs.", "ms.", "dr.", "prof.", "sr.", "jr.", "st.", "vs.", "etc.", "e.g.", "i.e.", "cf.", "no.", "fig.", "eq.", "inc.", "ltd.", "co.", "dept.", "mt.", "ft."]
        if known.contains(lowered) { return true }
        guard lowered.hasSuffix(".") else { return false }
        if isDottedInitialism(word) { return true }
        if readableCharacterCount(lowered) <= 2 { return true }
        if nextWordStartsLowercase && readableCharacterCount(lowered) <= 4 { return true }
        return false
    }

    private static func percentOf(_ value: Int, _ percent: Int) -> Int { (value * percent) / 100 }
    private static func clampScalePercent(_ percent: Int) -> Int { min(200, max(25, percent)) }
    private static func scaledPercent(_ base: Int, _ scale: Int) -> Int { (base * clampScalePercent(scale)) / 100 }

    private static func lengthBonusPercentForWord(_ word: String) -> Int {
        let readable = readableCharacterCount(word)
        guard readable > 0 else { return 0 }
        var bonus = 0
        if readable > 6 { bonus += (readable - 6) * 6 }
        if readable > 10 { bonus += (readable - 10) * 9 }
        if readable > 14 { bonus += (readable - 14) * 12 }
        let joiners = connectorCount(word, predicate: isSegmentSeparator)
        if joiners > 0 {
            bonus += joiners * 14
            if readable >= 10 { bonus += 18 }
        }
        let tech = connectorCount(word, predicate: isTechnicalConnector)
        if tech > joiners { bonus += (tech - joiners) * 8 }
        return min(170, bonus)
    }

    private static func complexityBonusPercentForWord(_ word: String) -> Int {
        var bonus = 0
        let syllables = approximateSyllableGroupCount(word)
        if syllables > 2 { bonus += min(50, (syllables - 2) * 10) }
        let letters = letterCharacterCount(word)
        let digits = digitCharacterCount(word)
        let uppercase = uppercaseLetterCount(word)
        if letters > 0 && digits > 0 { bonus += 22 }
        else if digits >= 3 { bonus += 10 }
        if uppercase >= 2 && uppercase == letters { bonus += 14 }
        let tech = connectorCount(word, predicate: isTechnicalConnector)
        if tech >= 2 { bonus += (tech - 1) * 12 }
        return min(85, bonus)
    }

    private static func punctuationPausePercentForWord(_ word: String, nextWordStartsLowercase: Bool) -> Int {
        if trailingRepeatedCharCount(word, target: ".") >= 3 { return 110 }
        switch trailingRhythmChar(word) {
        case ",": return 45
        case "-": return 60
        case ";", ":": return 80
        case ".":
            return looksLikeAbbreviation(word, nextWordStartsLowercase: nextWordStartsLowercase) ? 0 : 135
        case "!", "?": return 150
        default: return 0
        }
    }

    static func durationForWord(_ word: String, nextWordStartsLowercase: Bool, baseIntervalMs: Int, config: PacingConfig) -> Int {
        guard !word.isEmpty, baseIntervalMs > 0 else { return baseIntervalMs }
        var total = 0
        total += scaledPercent(lengthBonusPercentForWord(word), config.longWordScalePercent)
        total += scaledPercent(complexityBonusPercentForWord(word), config.complexWordScalePercent)
        total += scaledPercent(punctuationPausePercentForWord(word, nextWordStartsLowercase: nextWordStartsLowercase), config.punctuationScalePercent)
        total = min(280, total)
        return baseIntervalMs + percentOf(baseIntervalMs, total)
    }
}

