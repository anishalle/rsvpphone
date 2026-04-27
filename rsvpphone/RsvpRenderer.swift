import UIKit

final class RsvpRenderer {
    static let logicalSize = CGSize(width: 640, height: 172)

    struct ContextWord: Equatable {
        var text: String
        var paragraphStart: Bool
        var current: Bool
    }

    struct LibraryItem: Equatable {
        var title: String
        var subtitle: String
    }

    private let baseFontName = "AvenirNext-Regular"
    private let tinyFontName = "Menlo-Regular"
    private let footerHorizontalInset: CGFloat = 24
    private let footerBottomInset: CGFloat = 26
    private var activeSize = RsvpRenderer.logicalSize

    func render(_ context: RenderContext, size: CGSize = RsvpRenderer.logicalSize) -> UIImage {
        activeSize = size
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { imageContext in
            let cg = imageContext.cgContext
            fillBackground(cg, settings: context.settings)
            if let title = context.statusTitle {
                drawStatus(cg, title: title, line1: context.statusLine1, line2: context.statusLine2, progress: context.progressValue, settings: context.settings)
            } else if !context.libraryItems.isEmpty {
                drawLibrary(cg, context: context)
            } else if !context.menuItems.isEmpty {
                drawMenu(cg, context: context)
            } else if !context.contextWords.isEmpty {
                drawContext(cg, context: context)
            } else {
                drawReader(cg, context: context)
            }
        }
    }

    private func fillBackground(_ cg: CGContext, settings: ReaderSettings) {
        backgroundColor(settings).setFill()
        cg.fill(CGRect(origin: .zero, size: activeSize))
    }

    private func drawReader(_ cg: CGContext, context: RenderContext) {
        let settings = context.settings
        let current = context.word
        let fontSize = [58.0, 42.0, 30.0][safe: settings.fontSizeLevel] ?? 58.0
        let font = UIFont(name: baseFontName, size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .regular)
        let y = (activeSize.height - font.lineHeight) / 2 - font.descender / 2
        let anchorX = activeSize.width * CGFloat(settings.typography.anchorPercent) / 100.0
        let focus = focusLetterIndex(current)
        let startX = rsvpStartX(word: current, focusIndex: focus, anchorX: anchorX, font: font, tracking: settings.typography.trackingPx)
        drawAnchorGuide(cg, anchorX: anchorX, textY: y, textHeight: font.lineHeight, settings: settings)

        if !context.beforeText.isEmpty {
            let beforeFont = font
            let gap = CGFloat([30, 24, 20][safe: settings.fontSizeLevel] ?? 30)
            let beforeWidth = measuredWidth(context.beforeText, font: beforeFont, tracking: settings.typography.trackingPx)
            drawText(context.beforeText, at: CGPoint(x: startX - beforeWidth - gap, y: y), font: beforeFont, color: wordColor(settings).withAlphaComponent(0.24), tracking: settings.typography.trackingPx)
        }
        drawRsvpWord(current, x: startX, y: y, focusIndex: focus, font: font, settings: settings)
        if !context.afterText.isEmpty {
            let currentWidth = measuredWidth(current, font: font, tracking: settings.typography.trackingPx)
            let gap = CGFloat([30, 24, 20][safe: settings.fontSizeLevel] ?? 30)
            let x = startX + currentWidth + gap
            drawText(context.afterText, at: CGPoint(x: x, y: y), font: font, color: wordColor(settings).withAlphaComponent(0.24), tracking: settings.typography.trackingPx)
        }
        if let wpm = context.wpmFeedback {
            drawTiny("\(wpm) WPM", centeredY: activeSize.height - 48, color: focusColor(settings), settings: settings)
        }
        if context.showFooter {
            drawFooter(context.chapterLabel, progress: context.progressPercent, settings: settings)
        }
    }

    private func drawContext(_ cg: CGContext, context: RenderContext) {
        let font = UIFont(name: baseFontName, size: 21) ?? .systemFont(ofSize: 21)
        let lineHeight: CGFloat = 23
        let marginX: CGFloat = 18
        var lines: [[ContextWord]] = []
        var line: [ContextWord] = []
        var lineWidth: CGFloat = 0
        let maxWidth = activeSize.width - marginX * 2
        for word in context.contextWords {
            if word.paragraphStart, !line.isEmpty {
                lines.append(line)
                line = []
                lineWidth = 0
            }
            let width = measuredWidth(word.text, font: font, tracking: 0)
            if !line.isEmpty, lineWidth + 8 + width > maxWidth {
                lines.append(line)
                line = []
                lineWidth = 0
            }
            line.append(word)
            lineWidth += (line.count == 1 ? 0 : 8) + width
        }
        if !line.isEmpty { lines.append(line) }
        let currentLine = lines.firstIndex { $0.contains { $0.current } } ?? 0
        let first = max(0, min(max(0, lines.count - 6), currentLine - 2))
        var y: CGFloat = 8
        for line in lines.dropFirst(first).prefix(6) {
            var x = marginX + ((line.first?.paragraphStart ?? false) ? 22 : 0)
            for word in line {
                drawText(word.text, at: CGPoint(x: x, y: y), font: font, color: word.current ? focusColor(context.settings) : wordColor(context.settings), tracking: 0)
                x += measuredWidth(word.text, font: font, tracking: 0) + 8
            }
            y += lineHeight
        }
        drawFooter(context.chapterLabel, progress: context.progressPercent, settings: context.settings)
    }

    private func drawMenu(_ cg: CGContext, context: RenderContext) {
        let rowHeight: CGFloat = 22
        let visible = min(context.menuItems.count, max(1, Int(activeSize.height / rowHeight)))
        var first = 0
        if context.selectedIndex >= visible / 2 { first = context.selectedIndex - visible / 2 }
        if first + visible > context.menuItems.count { first = max(0, context.menuItems.count - visible) }
        var y = max(0, (activeSize.height - CGFloat(visible) * rowHeight) / 2)
        for row in 0..<visible {
            let index = first + row
            let selected = index == context.selectedIndex
            if selected {
                selectedBarColor(context.settings).setFill()
                cg.fill(CGRect(x: 10, y: y + 2, width: 5, height: 16))
            }
            drawTiny(context.menuItems[index], at: CGPoint(x: 28, y: y + 3), color: selected ? focusColor(context.settings) : dimColor(context.settings), settings: context.settings)
            y += rowHeight
        }
    }

    private func drawLibrary(_ cg: CGContext, context: RenderContext) {
        let rowHeight: CGFloat = 38
        let visible = min(context.libraryItems.count, 3)
        var first = 0
        if context.selectedIndex >= visible / 2 { first = context.selectedIndex - visible / 2 }
        if first + visible > context.libraryItems.count { first = max(0, context.libraryItems.count - visible) }
        var y = max(28, (activeSize.height - CGFloat(visible) * rowHeight) / 2)
        for row in 0..<visible {
            let index = first + row
            let item = context.libraryItems[index]
            let selected = index == context.selectedIndex
            if selected {
                selectedBarColor(context.settings).setFill()
                cg.fill(CGRect(x: 10, y: y + 3, width: 5, height: rowHeight - 6))
            }
            drawTiny(item.title, at: CGPoint(x: 26, y: y + 4), color: selected ? focusColor(context.settings) : wordColor(context.settings), settings: context.settings)
            if !item.subtitle.isEmpty {
                drawTiny(item.subtitle, at: CGPoint(x: 26, y: y + 20), color: dimColor(context.settings), settings: context.settings)
            }
            y += rowHeight
        }
    }

    private func drawStatus(_ cg: CGContext, title: String, line1: String, line2: String, progress: Int?, settings: ReaderSettings) {
        let font = UIFont(name: baseFontName, size: 48) ?? .systemFont(ofSize: 48)
        drawCentered(title, y: activeSize.height * 0.28, font: font, color: wordColor(settings), settings: settings)
        drawTiny(line1, centeredY: activeSize.height * 0.63, color: dimColor(settings), settings: settings)
        drawTiny(line2, centeredY: activeSize.height * 0.76, color: focusColor(settings), settings: settings)
        if let progress {
            let barWidth = min(300, activeSize.width - 120)
            let bar = CGRect(x: (activeSize.width - barWidth) / 2, y: activeSize.height - 22, width: barWidth, height: 8)
            dimColor(settings).setFill()
            cg.fill(bar)
            backgroundColor(settings).setFill()
            cg.fill(bar.insetBy(dx: 1, dy: 1))
            focusColor(settings).setFill()
            cg.fill(CGRect(x: bar.minX + 1, y: bar.minY + 1, width: max(1, CGFloat(progress) / 100 * (bar.width - 2)), height: bar.height - 2))
        }
    }

    private func drawRsvpWord(_ word: String, x: CGFloat, y: CGFloat, focusIndex: Int, font: UIFont, settings: ReaderSettings) {
        var cursor = x
        for (idx, ch) in Array(word).enumerated() {
            let s = String(ch)
            let color = idx == focusIndex ? focusColor(settings) : wordColor(settings)
            drawText(s, at: CGPoint(x: cursor, y: y), font: font, color: color, tracking: settings.typography.trackingPx)
            cursor += measuredWidth(s, font: font, tracking: settings.typography.trackingPx)
        }
    }

    private func drawFooter(_ chapter: String, progress: Int, settings: ReaderSettings) {
        let y = activeSize.height - footerBottomInset
        drawTiny(chapter.isEmpty ? "START" : chapter, at: CGPoint(x: footerHorizontalInset, y: y), color: footerColor(settings), settings: settings)
        let pct = "\(progress)%"
        let width = tinyWidth(pct)
        drawTiny(pct, at: CGPoint(x: activeSize.width - footerHorizontalInset - width, y: y), color: footerColor(settings), settings: settings)
    }

    private func drawAnchorGuide(_ cg: CGContext, anchorX: CGFloat, textY: CGFloat, textHeight: CGFloat, settings: ReaderSettings) {
        let top = max(2, textY - 7)
        let bottom = min(activeSize.height - 3, textY + textHeight + 7)
        let half = CGFloat(settings.typography.guideHalfWidth)
        let gap = CGFloat(settings.typography.guideGap)
        wordColor(settings).withAlphaComponent(settings.theme == .night ? 0.53 : 0.38).setFill()
        cg.fill(CGRect(x: anchorX - half, y: top, width: max(0, half - gap), height: 1))
        cg.fill(CGRect(x: anchorX + gap, y: top, width: max(0, half - gap), height: 1))
        cg.fill(CGRect(x: anchorX - half, y: bottom, width: max(0, half - gap), height: 1))
        cg.fill(CGRect(x: anchorX + gap, y: bottom, width: max(0, half - gap), height: 1))
        focusColor(settings).setFill()
        cg.fill(CGRect(x: anchorX, y: top, width: 1, height: 5))
        cg.fill(CGRect(x: anchorX, y: bottom - 4, width: 1, height: 5))
    }

    private func drawCentered(_ text: String, y: CGFloat, font: UIFont, color: UIColor, settings: ReaderSettings) {
        let width = measuredWidth(text, font: font, tracking: settings.typography.trackingPx)
        drawText(text, at: CGPoint(x: (activeSize.width - width) / 2, y: y), font: font, color: color, tracking: settings.typography.trackingPx)
    }

    private func drawText(_ text: String, at point: CGPoint, font: UIFont, color: UIColor, tracking: Int) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: tracking
        ]
        text.draw(at: point, withAttributes: attrs)
    }

    private func drawTiny(_ text: String, centeredY y: CGFloat, color: UIColor, settings: ReaderSettings) {
        drawTiny(text, at: CGPoint(x: (activeSize.width - tinyWidth(text)) / 2, y: y), color: color, settings: settings)
    }

    private func drawTiny(_ text: String, at point: CGPoint, color: UIColor, settings: ReaderSettings) {
        let font = UIFont(name: tinyFontName, size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        let fitted = fit(text, maxWidth: activeSize.width - point.x - 12, font: font)
        fitted.draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func tinyWidth(_ text: String) -> CGFloat {
        let font = UIFont(name: tinyFontName, size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        return measuredWidth(text, font: font, tracking: 0)
    }

    private func fit(_ text: String, maxWidth: CGFloat, font: UIFont) -> String {
        guard measuredWidth(text, font: font, tracking: 0) > maxWidth else { return text }
        var fitted = text
        while !fitted.isEmpty, measuredWidth(fitted + "...", font: font, tracking: 0) > maxWidth {
            fitted.removeLast()
        }
        return fitted.isEmpty ? "..." : fitted + "..."
    }

    private func fitPrefixWords(_ text: String, maxWidth: CGFloat, font: UIFont, tracking: Int) -> String {
        guard maxWidth > 0 else { return "" }
        let words = text.split(separator: " ").map(String.init)
        var fitted: [String] = []
        for word in words {
            let candidate = (fitted + [word]).joined(separator: " ")
            if measuredWidth(candidate, font: font, tracking: tracking) > maxWidth { break }
            fitted.append(word)
        }
        return fitted.joined(separator: " ")
    }

    private func fitSuffixWords(_ text: String, maxWidth: CGFloat, font: UIFont, tracking: Int) -> String {
        guard maxWidth > 0 else { return "" }
        let words = text.split(separator: " ").map(String.init)
        var fitted: [String] = []
        for word in words.reversed() {
            let candidate = ([word] + fitted).joined(separator: " ")
            if measuredWidth(candidate, font: font, tracking: tracking) > maxWidth { break }
            fitted.insert(word, at: 0)
        }
        return fitted.joined(separator: " ")
    }

    private func measuredWidth(_ text: String, font: UIFont, tracking: Int) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: tracking]
        return ceil((text as NSString).size(withAttributes: attrs).width)
    }

    private func rsvpStartX(word: String, focusIndex: Int, anchorX: CGFloat, font: UIFont, tracking: Int) -> CGFloat {
        guard focusIndex >= 0 else {
            return (activeSize.width - measuredWidth(word, font: font, tracking: tracking)) / 2
        }
        var before = ""
        let chars = Array(word)
        if focusIndex > 0 { before = String(chars[0..<focusIndex]) }
        let focus = String(chars[focusIndex])
        let center = measuredWidth(before, font: font, tracking: tracking) + measuredWidth(focus, font: font, tracking: tracking) / 2
        return anchorX - center
    }

    func focusLetterIndex(_ word: String) -> Int {
        let chars = Array(word)
        let wordIndices = chars.indices.filter { chars[$0].isLetter || chars[$0].isNumber }
        guard !wordIndices.isEmpty else { return chars.isEmpty ? -1 : 0 }
        let count = wordIndices.count
        let ordinal: Int
        if count <= 1 { ordinal = 0 }
        else if count <= 5 { ordinal = 1 }
        else if count <= 9 { ordinal = 2 }
        else if count <= 13 { ordinal = 3 }
        else { ordinal = 4 }
        return wordIndices[min(ordinal, count - 1)]
    }

    private func backgroundColor(_ settings: ReaderSettings) -> UIColor {
        switch settings.theme {
        case .dark, .night: return .black
        case .light: return .white
        }
    }

    private func wordColor(_ settings: ReaderSettings) -> UIColor {
        switch settings.theme {
        case .dark: return .white
        case .light: return .black
        case .night: return UIColor(red: 1.0, green: 0.81, blue: 0.0, alpha: 1)
        }
    }

    private func focusColor(_ settings: ReaderSettings) -> UIColor {
        switch settings.theme {
        case .night: return UIColor(red: 1.0, green: 0.65, blue: 0.0, alpha: 1)
        default: return .red
        }
    }

    private func dimColor(_ settings: ReaderSettings) -> UIColor {
        switch settings.theme {
        case .light: return UIColor(white: 0.42, alpha: 1)
        default: return UIColor(white: 0.52, alpha: 1)
        }
    }

    private func footerColor(_ settings: ReaderSettings) -> UIColor {
        switch settings.theme {
        case .light: return UIColor(white: 0.36, alpha: 1)
        case .night: return UIColor(red: 1.0, green: 0.81, blue: 0.0, alpha: 0.52)
        case .dark: return UIColor(white: 0.32, alpha: 1)
        }
    }

    private func selectedBarColor(_ settings: ReaderSettings) -> UIColor {
        focusColor(settings).withAlphaComponent(0.7)
    }
}
