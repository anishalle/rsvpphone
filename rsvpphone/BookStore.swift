import Foundation

final class BookStore {
    private let root: URL
    private let recordsURL: URL
    private var records: [BookRecord] = []
    private var nextRecentSequence = 0

    init(fileManager: FileManager = .default) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        root = documents.appendingPathComponent("Books", isDirectory: true)
        recordsURL = documents.appendingPathComponent("book-records.json")
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        load()
    }

    func allRecords() -> [BookRecord] {
        records.sorted {
            if $0.recentSequence != $1.recentSequence { return $0.recentSequence > $1.recentSequence }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func content(for record: BookRecord) throws -> BookContent {
        try BookParser.parse(url: record.path)
    }

    @discardableResult
    func importBook(from source: URL) throws -> BookRecord {
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { source.stopAccessingSecurityScopedResource() }
        }
        let content = try BookParser.parse(url: source)
        let filename = uniqueFilename(source.lastPathComponent.isEmpty ? "book.rsvp" : source.lastPathComponent)
        let destination = root.appendingPathComponent(filename)
        if source.pathExtension.lowercased() == "rsvp" {
            try FileManager.default.copyItem(at: source, to: destination)
        } else {
            try BookParser.rsvpData(from: content, source: source.lastPathComponent).write(to: destination)
        }

        nextRecentSequence += 1
        let record = BookRecord(
            path: destination,
            title: content.title.isEmpty ? destination.deletingPathExtension().lastPathComponent : content.title,
            author: content.author,
            wordCount: content.words.count,
            currentWordIndex: 0,
            recentSequence: nextRecentSequence
        )
        records.removeAll { $0.path == destination || $0.path.lastPathComponent == destination.lastPathComponent }
        records.append(record)
        save()
        return record
    }

    func updateProgress(path: URL, wordIndex: Int, wordCount: Int) {
        guard let idx = records.firstIndex(where: { $0.path == path }) else { return }
        nextRecentSequence += 1
        records[idx].currentWordIndex = max(0, min(wordIndex, max(0, wordCount - 1)))
        records[idx].wordCount = wordCount
        records[idx].recentSequence = nextRecentSequence
        save()
    }

    private func uniqueFilename(_ raw: String) -> String {
        let base = URL(fileURLWithPath: raw).deletingPathExtension().lastPathComponent
        let ext = "rsvp"
        var name = "\(base).\(ext)"
        var counter = 2
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) {
            name = "\(base)-\(counter).\(ext)"
            counter += 1
        }
        return name
    }

    private func load() {
        guard let data = try? Data(contentsOf: recordsURL),
              let decoded = try? JSONDecoder().decode([BookRecord].self, from: data) else {
            return
        }
        records = decoded.filter { FileManager.default.fileExists(atPath: $0.path.path) }
        nextRecentSequence = records.map(\.recentSequence).max() ?? 0
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: recordsURL, options: .atomic)
        }
    }
}

