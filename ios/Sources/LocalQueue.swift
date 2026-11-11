import Foundation
import CryptoKit

/// Encrypted-by-iOS-sandbox local persistence, scoped to the signed-in Google account.
/// A pending health measurement must never be uploaded into another person's spreadsheet.
actor LocalQueue {
    static let shared = LocalQueue()
    private let baseDirectory: URL
    private var accountIdentifier = "offline"
    private var pending: [ExportRow] = []
    private var completed: Set<String> = []

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OraNaplo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        baseDirectory = dir
    }

    private var accountDirectory: URL {
        baseDirectory.appendingPathComponent("account-\(accountIdentifier)", isDirectory: true)
    }
    private var pendingFile: URL { accountDirectory.appendingPathComponent("queue.json") }
    private var completedFile: URL { accountDirectory.appendingPathComponent("exported_ids.json") }

    func selectAccount(_ email: String) throws {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { throw QueueError.missingAccount }
        let hash = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        let key = String(hash.prefix(24))
        guard key != accountIdentifier else { return }
        accountIdentifier = key
        try FileManager.default.createDirectory(at: accountDirectory, withIntermediateDirectories: true)
        pending = (try? Data(contentsOf: pendingFile)).flatMap { try? JSONDecoder().decode([ExportRow].self, from: $0) } ?? []
        completed = (try? Data(contentsOf: completedFile)).flatMap { try? JSONDecoder().decode(Set<String>.self, from: $0) } ?? []
    }

    private func savePending() throws {
        try JSONEncoder().encode(pending).write(to: pendingFile, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    private func saveCompleted() throws {
        try JSONEncoder().encode(completed).write(to: completedFile, options: [.atomic, .completeFileProtectionUnlessOpen])
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
        for row in rows { completed.insert(row.id) }
        try saveCompleted()
        let ids = Set(rows.map(\.id))
        pending.removeAll { ids.contains($0.id) }
        try savePending()
    }
    /// On downgrade purge premium records waiting for upload, including journals,
    /// HRV and workouts. Already exported Google Sheets cells are the user's own.
    func restrictToFreeTier() throws {
        pending.removeAll { row in
            row.sheet != "Pulzus" || row.values.count < 2 || row.values[1] != "Pulzus"
        }
        try savePending()
    }
    func count() -> Int { pending.count }
    func isUploaded(_ id: String) -> Bool { completed.contains(id) }
}

enum QueueError: LocalizedError {
    case missingAccount
    var errorDescription: String? { "Először jelentkezz be a Google-fiókodba." }
}
