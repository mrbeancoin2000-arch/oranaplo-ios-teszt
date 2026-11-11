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
    private var uncertain: [ExportRow] = []

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
    private var completedFile: URL { accountDirectory.appendingPathComponent("exported_ids.json") } // legacy import
    private var completedLogFile: URL { accountDirectory.appendingPathComponent("completed_ids.log") }
    private var uncertainFile: URL { accountDirectory.appendingPathComponent("uncertain_upload.json") }

    private func accountKey(for email: String) -> String {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hash = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
        return String(hash.prefix(24))
    }
    private func decodeExisting<T: Decodable>(_ path: URL, as: T.Type, empty: T) throws -> T {
        guard FileManager.default.fileExists(atPath: path.path) else { return empty }
        // Never silently replace a corrupted health queue with an empty queue.
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: path))
    }
    func selectAccount(_ email: String) throws {
        let value = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { throw QueueError.missingAccount }
        let key = accountKey(for: value)
        guard key != accountIdentifier else { return }
        let dir = baseDirectory.appendingPathComponent("account-\(key)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let incomingPending = try decodeExisting(dir.appendingPathComponent("queue.json"), as: [ExportRow].self, empty: [])
        let legacyIDs = try decodeExisting(dir.appendingPathComponent("exported_ids.json"), as: Set<String>.self, empty: [])
        let logURL = dir.appendingPathComponent("completed_ids.log")
        var incomingCompleted = legacyIDs
        if FileManager.default.fileExists(atPath: logURL.path) {
            let text = try String(contentsOf: logURL, encoding: .utf8)
            incomingCompleted.formUnion(text.split(separator: "\n").map(String.init))
        }
        let incomingUncertain = try decodeExisting(dir.appendingPathComponent("uncertain_upload.json"), as: [ExportRow].self, empty: [])
        accountIdentifier = key
        completed = incomingCompleted
        pending = incomingPending.filter { !incomingCompleted.contains($0.id) }
        uncertain = incomingUncertain.filter { !incomingCompleted.contains($0.id) }
        if pending.count != incomingPending.count { try savePending() }
        if uncertain.count != incomingUncertain.count { try saveUncertain() }
    }
    func enqueue(_ rows: [ExportRow], forAccount email: String? = nil) throws {
        if let email, accountKey(for: email) != accountIdentifier { throw QueueError.accountSwitched }
        var existing = Set(pending.map(\.id))
        for row in rows where !completed.contains(row.id) {
            if existing.insert(row.id).inserted { pending.append(row) }
        }
        try savePending()
    }
    func uncertainBatch() -> [ExportRow] { uncertain }
    func beginUpload(_ rows: [ExportRow]) throws {
        guard uncertain.isEmpty else { throw QueueError.uncertainUpload }
        uncertain = rows
        try saveUncertain()
    }
    func clearUncertain() throws { uncertain = []; try saveUncertain() }
    private func saveUncertain() throws {
        try JSONEncoder().encode(uncertain).write(to: uncertainFile, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    private func savePending() throws {
        try JSONEncoder().encode(pending).write(to: pendingFile, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    private func appendCompletedIDs(_ ids: Set<String>) throws {
        guard !ids.isEmpty else { return }
        if !FileManager.default.fileExists(atPath: completedLogFile.path) {
            try Data().write(to: completedLogFile, options: [.atomic, .completeFileProtectionUnlessOpen])
        }
        let file = try FileHandle(forWritingTo: completedLogFile)
        defer { try? file.close() }
        try file.seekToEnd()
        let data = Data((ids.sorted().joined(separator: "\n") + "\n").utf8)
        try file.write(contentsOf: data)
        try file.synchronize()
    }
    func nextBatch(limit: Int = 150) -> [ExportRow] {
        guard let first = pending.first(where: { !completed.contains($0.id) }) else { return [] }
        return Array(pending.filter { $0.sheet == first.sheet && !completed.contains($0.id) }.prefix(limit))
    }
    func didUpload(_ rows: [ExportRow]) throws {
        let freshIDs = Set(rows.map(\.id)).subtracting(completed)
        // Appending a short journal batch is O(batch), not a rewrite of all
        // 5-year HealthKit identifiers after every 150-sheet-row upload.
        try appendCompletedIDs(freshIDs)
        completed.formUnion(freshIDs)
        let ids = Set(rows.map(\.id))
        pending.removeAll { ids.contains($0.id) }
        try savePending()
        // Acknowledgement is durable only after both completed and pending files are saved.
        let idsInFlight = Set(uncertain.map(\.id))
        if idsInFlight.isSubset(of: completed) { try clearUncertain() }
    }
    /// On downgrade purge premium records waiting for upload, including journals,
    /// HRV and workouts. Already exported Google Sheets cells are the user's own.
    func restrictToFreeTier() throws {
        pending.removeAll { row in
            row.sheet != "Pulzus" || row.values.count < 2 || row.values[1] != "Pulzus"
        }
        try savePending()
        // Premium rows may not be retried after expiry, even if they were in-flight.
        uncertain.removeAll { $0.sheet != "Pulzus" || $0.values.count < 2 || $0.values[1] != "Pulzus" }
        try saveUncertain()
    }
    func count() -> Int { pending.count }
    func completedCount() -> Int { completed.count }
    func isUploaded(_ id: String) -> Bool { completed.contains(id) }
}

enum QueueError: LocalizedError {
    case missingAccount, accountSwitched, uncertainUpload
    var errorDescription: String? {
        switch self {
        case .missingAccount: return "Először jelentkezz be a Google-fiókodba."
        case .accountSwitched: return "Google-fiókváltás történt; az importot újra kell kezdeni."
        case .uncertainUpload: return "Előbb egyeztetni kell az előző bizonytalan feltöltést."
        }
    }
}
