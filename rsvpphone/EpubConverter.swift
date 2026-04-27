import Foundation
import Compression

enum EpubConverter {
    static func convert(url: URL) throws -> BookContent {
        let archive = try ZipArchive(data: Data(contentsOf: url))
        let container = try archive.text(named: "META-INF/container.xml")
        guard let opfPath = firstMatch(in: container, pattern: #"full-path\s*=\s*"([^"]+)""#) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let opf = try archive.text(named: opfPath)
        let title = firstTagText("dc:title", in: opf) ?? firstTagText("title", in: opf) ?? url.deletingPathExtension().lastPathComponent
        let author = firstTagText("dc:creator", in: opf) ?? firstTagText("creator", in: opf) ?? ""
        let manifest = manifestItems(opf: opf, opfPath: opfPath)
        let spineIds = matches(in: opf, pattern: #"<itemref[^>]*idref\s*=\s*"([^"]+)""#).map { $0[0] }
        var events: [(kind: String, value: String)] = []

        for (index, id) in spineIds.enumerated() {
            guard let item = manifest[id], item.path.lowercased().range(of: #"\.(xhtml|html|htm)$"#, options: .regularExpression) != nil else { continue }
            let html = try archive.text(named: item.path)
            var chapterEvents = BookParser.htmlEvents(html)
            guard chapterEvents.contains(where: { $0.kind == "text" }) else { continue }
            if !chapterEvents.contains(where: { $0.kind == "chapter" }) {
                chapterEvents.insert(("chapter", fallbackChapterTitle(path: item.path, index: index + 1)), at: 0)
            }
            events.append(contentsOf: chapterEvents)
        }

        return BookParser.parseEvents(events, title: title, author: author)
    }

    private static func firstTagText(_ tag: String, in xml: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        return firstMatch(in: xml, pattern: #"(?is)<"# + escaped + #"[^>]*>(.*?)</"# + escaped + #">"#)
            .map { TextNormalizer.cleanText($0) }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        matches(in: text, pattern: pattern).first?.first
    }

    private static func matches(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (1..<match.numberOfRanges).compactMap { index in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return ns.substring(with: range)
            }
        }
    }

    private static func manifestItems(opf: String, opfPath: String) -> [String: (path: String, media: String)] {
        var items: [String: (String, String)] = [:]
        for m in matches(in: opf, pattern: #"<item\b([^>]*)>"#) {
            guard let attrs = m.first,
                  let id = firstMatch(in: attrs, pattern: #"id\s*=\s*"([^"]+)""#),
                  let href = firstMatch(in: attrs, pattern: #"href\s*=\s*"([^"]+)""#) else { continue }
            let media = firstMatch(in: attrs, pattern: #"media-type\s*=\s*"([^"]+)""#) ?? ""
            items[id] = (zipJoin(base: opfPath, href: href), media)
        }
        return items
    }

    private static func zipJoin(base: String, href: String) -> String {
        let decoded = href.components(separatedBy: "#")[0].removingPercentEncoding ?? href
        let baseDir = (base as NSString).deletingLastPathComponent
        return (NSString.path(withComponents: [baseDir, decoded]) as NSString).standardizingPath
    }

    private static func fallbackChapterTitle(path: String, index: Int) -> String {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let cleaned = TextNormalizer.cleanText(stem.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " "))
        return cleaned.isEmpty ? "Chapter \(index)" : cleaned
    }
}

struct ZipArchive {
    struct Entry {
        var method: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var dataOffset: Int
    }

    let data: Data
    let entries: [String: Entry]

    init(data: Data) throws {
        self.data = data
        var parsed: [String: Entry] = [:]
        var offset = 0
        while offset + 30 <= data.count {
            guard data.uint32(at: offset) == 0x04034b50 else { break }
            let method = data.uint16(at: offset + 8)
            let compressed = Int(data.uint32(at: offset + 18))
            let uncompressed = Int(data.uint32(at: offset + 22))
            let nameLen = Int(data.uint16(at: offset + 26))
            let extraLen = Int(data.uint16(at: offset + 28))
            let nameStart = offset + 30
            let payload = nameStart + nameLen + extraLen
            guard payload + compressed <= data.count else { break }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLen))
            if let name = String(data: nameData, encoding: .utf8) {
                parsed[name] = Entry(method: method, compressedSize: compressed, uncompressedSize: uncompressed, dataOffset: payload)
            }
            offset = payload + compressed
        }
        entries = parsed
    }

    func text(named name: String) throws -> String {
        let normalized = name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let entry = entries[normalized] else { throw CocoaError(.fileNoSuchFile) }
        let bytes = try contents(of: entry)
        return BookParser.decodeText(bytes)
    }

    private func contents(of entry: Entry) throws -> Data {
        let payload = data.subdata(in: entry.dataOffset..<(entry.dataOffset + entry.compressedSize))
        if entry.method == 0 { return payload }
        if entry.method == 8 {
            return try inflateRaw(payload, expectedSize: entry.uncompressedSize)
        }
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    private func inflateRaw(_ payload: Data, expectedSize: Int) throws -> Data {
        var output = Data(count: max(expectedSize, payload.count * 4, 4096))
        let outputCapacity = output.count
        let decoded = output.withUnsafeMutableBytes { outPtr in
            payload.withUnsafeBytes { inPtr in
                compression_decode_buffer(
                    outPtr.bindMemory(to: UInt8.self).baseAddress!,
                    outputCapacity,
                    inPtr.bindMemory(to: UInt8.self).baseAddress!,
                    payload.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decoded > 0 else { throw CocoaError(.fileReadCorruptFile) }
        output.count = decoded
        return output
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) | (UInt32(self[offset + 1]) << 8) | (UInt32(self[offset + 2]) << 16) | (UInt32(self[offset + 3]) << 24)
    }
}
