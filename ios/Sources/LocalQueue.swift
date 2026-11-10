import Foundation

/// Durable on-device queue. Nothing is uploaded to an ÓraNapló-owned server.
actor LocalQueue {
    static let shared = LocalQueue()
    private var pending: [ExportRow] = []
    private var completed: Set<String> = []
    private let pendingFile: URL
    private let completedFile: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OraNaplo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pendingFile = dir.appendingPathComponent("queue.json")
        completedFile = dir.appendingPathComponent("exported_ids.json")
        if let d = try? Data(contentsOf: pendingFile), let rows = try? JSONDecoder().decode([ExportRow].self, from: d) { pending = rows }
        if let d = try? Data(contentsOf: completedFile), let ids = try? JSONDecoder().decode(Set<String>.self, from: d) { completed = ids }
    }
    private func savePending() throws {
        let data = try JSONEncoder().encode(pending)
        try data.write(to: pendingFile, options: .atomic)
    }
    private func saveCompleted() throws {
        let data = try JSONEncoder().encode(completed)
        try data.write(to: completedFile, options: .atomic)
    }
    func enqueue(_ rows: [ExportRow]) throws {
        let existing = Set(pending.map(\.id))
        pending += rows.filter { !completed.contains($0.id) && !existing.contains($0.id) }
        try savePending()
    }
    func nextBatch(limit: Int = 150) -> [ExportRow] {
        guard let first = pending.first else { return [] }
        return Array(pending.filter { $0.sheet == first.sheet }.prefix(limit))
    }
    func didUpload(_ rows: [ExportRow]) throws {
        // Persist delivered identifiers before removing queue entries. If disk write fails,
        // they stay in queue and are not silently dropped.
        for row in rows { completed.insert(row.id) }
        try saveCompleted()
        let ids = Set(rows.map(\.id))
        pending.removeAll { ids.contains($0.id) }
        try savePending()
    }
    func count() -> Int { pending.count }
    func isUploaded(_ id: String) -> Bool { completed.contains(id) }
}
