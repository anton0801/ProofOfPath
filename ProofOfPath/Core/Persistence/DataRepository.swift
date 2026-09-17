//
//  DataRepository.swift
//  ProofOfPath
//
//  The offline cache of server data, plus backup files.
//

import Foundation

enum RepositoryError: LocalizedError {
    case encodeFailed(String)
    case decodeFailed(String)
    case writeFailed(String)
    case readFailed(String)
    case unsupportedSchema(Int)
    case tooLarge(Int64)

    var errorDescription: String? {
        switch self {
        case .encodeFailed(let detail): return "Could not prepare the data for saving. \(detail)"
        case .decodeFailed(let detail): return "The file could not be read as a ProofPath backup. \(detail)"
        case .writeFailed(let detail): return "Could not write to storage. \(detail)"
        case .readFailed(let detail): return "Could not read from storage. \(detail)"
        case .unsupportedSchema(let version): return "This backup was made by a newer version of the app (format \(version))."
        case .tooLarge(let bytes): return "That file is \(POPFormat.fileSize(bytes)). A ProofPath backup should be well under 50 MB."
        }
    }
}

/// What the cache file holds: the last data the server confirmed, and whose.
struct CachedAccountData: Codable {
    var userID: String
    var savedAt: Date
    var data: AppData
}

/// The server is the source of truth. This keeps a copy of what it last
/// confirmed so the app opens instantly and stays readable offline.
///
/// The cache is tied to the account that wrote it: data cached for one account
/// is never shown to another (after "Delete All Data", for example).
final class DataRepository {

    static let shared = DataRepository()

    private let fileName = "proofpath-cache.json"
    private let queue = DispatchQueue(label: "com.proofofpath.cache", qos: .utility)

    private let directoryOverride: URL?

    /// - Parameter directory: where the cache lives. Nil means Application
    ///   Support; tests pass a temporary directory.
    init(directory: URL? = nil) {
        self.directoryOverride = directory
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private var cacheDirectory: URL {
        if let directoryOverride { return directoryOverride }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ProofPath", isDirectory: true)
    }

    var storeURL: URL { cacheDirectory.appendingPathComponent(fileName) }

    private let encoder = POPJSON.makeEncoder()
    private let decoder = POPJSON.makeDecoder()

    // MARK: - Cache

    /// The cached data, if it belongs to `userID`.
    func load(for userID: String) -> AppData? {
        guard let raw = try? Data(contentsOf: storeURL), !raw.isEmpty,
              let cached = try? decoder.decode(CachedAccountData.self, from: raw),
              cached.userID == userID
        else { return nil }
        return cached.data
    }

    /// Debounced, atomic write on a background queue.
    private var pendingWorkItem: DispatchWorkItem?

    func save(_ data: AppData, for userID: String) {
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.writeNow(data, userID: userID)
        }
        pendingWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Forces an immediate write — used when the app is backgrounding.
    func flush(_ data: AppData, for userID: String) {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        queue.sync { [weak self] in
            self?.writeNow(data, userID: userID)
        }
    }

    private func writeNow(_ data: AppData, userID: String) {
        do {
            let encoded = try encoder.encode(CachedAccountData(userID: userID, savedAt: Date(), data: data))
            // Receipts, contacts and prices: unreadable while the device is locked.
            try encoded.write(to: storeURL, options: [.atomic, .completeFileProtection])
            var url = storeURL
            var values = URLResourceValues()
            // The server holds the real copy; the cache does not belong in iCloud backups.
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            #if DEBUG
            print("[ProofPath] Cache write failed: \(error.localizedDescription)")
            #endif
        }
    }

    func deleteStore() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        queue.sync {
            try? FileManager.default.removeItem(at: storeURL)
        }
    }

    // MARK: - Version 1.0 data

    /// Version 1.0 kept everything in Documents. That data is not migrated to
    /// the server; it is left untouched until the user deletes their data.
    var legacyStoreURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("proofpath-data.json")
    }

    func removeLegacyData() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in ["proofpath-data.json", "proofpath-data-unreadable.json"] {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
    }

    // MARK: - Export / Import

    func exportData(_ data: AppData) throws -> URL {
        do {
            let encoded = try POPJSON.makeEncoder(pretty: true).encode(data)
            // Exports are shared out of the app, so clear any previous copy first
            // rather than leaving a full data dump sitting in the temp folder.
            purgeTemporaryExports()
            let exportURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ProofPath-Backup-\(Self.exportStamp()).json")
            try encoded.write(to: exportURL, options: [.atomic, .completeFileProtection])
            return exportURL
        } catch {
            throw RepositoryError.encodeFailed(error.localizedDescription)
        }
    }

    func importData(from url: URL) throws -> AppData {
        var needsRelease = false
        if url.startAccessingSecurityScopedResource() { needsRelease = true }
        defer { if needsRelease { url.stopAccessingSecurityScopedResource() } }

        // Refuse an oversized file before reading it into memory.
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           Int64(size) > Self.maxImportBytes {
            throw RepositoryError.tooLarge(Int64(size))
        }

        let raw: Data
        do {
            raw = try Data(contentsOf: url)
        } catch {
            throw RepositoryError.readFailed(error.localizedDescription)
        }
        guard Int64(raw.count) <= Self.maxImportBytes else {
            throw RepositoryError.tooLarge(Int64(raw.count))
        }
        do {
            let decoded = try decoder.decode(AppData.self, from: raw)
            guard decoded.schemaVersion <= AppData.currentSchemaVersion else {
                throw RepositoryError.unsupportedSchema(decoded.schemaVersion)
            }
            return decoded
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.decodeFailed(error.localizedDescription)
        }
    }

    static let maxImportBytes: Int64 = 50 * 1024 * 1024

    /// Removes backup files this app previously wrote to the temp folder.
    func purgeTemporaryExports() {
        let tmp = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: tmp.path) else { return }
        for name in contents where name.hasPrefix("ProofPath-Backup-") || name.hasPrefix("ProofPath-Summary-") {
            try? FileManager.default.removeItem(at: tmp.appendingPathComponent(name))
        }
    }

    private static func exportStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}
