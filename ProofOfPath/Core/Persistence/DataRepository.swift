//
//  DataRepository.swift
//  ProofOfPath
//
//  Local JSON storage. No account, no network.
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

final class DataRepository {

    static let shared = DataRepository()

    private let fileName = "proofpath-data.json"
    private let queue = DispatchQueue(label: "com.proofofpath.persistence", qos: .utility)

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var storeURL: URL { documentsURL.appendingPathComponent(fileName) }

    /// Plain `.iso8601` truncates to whole seconds, which lets two events logged
    /// in the same second swap places after a reload. Fractional seconds keep the
    /// chronology exactly as it was recorded.
    private static let preciseFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private lazy var encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.preciseFormatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            // Accept both shapes so a file written by any build still opens.
            if let date = Self.preciseFormatter.date(from: text) { return date }
            if let date = Self.fallbackFormatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "“\(text)” is not an ISO-8601 date."
            )
        }
        return decoder
    }()

    // MARK: - Load

    func load() -> AppData {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return AppData() }
        do {
            let data = try Data(contentsOf: storeURL)
            guard !data.isEmpty else { return AppData() }
            return try decoder.decode(AppData.self, from: data)
        } catch {
            // Never destroy the user's file on a read failure — keep it for recovery.
            let backupURL = documentsURL.appendingPathComponent("proofpath-data-unreadable.json")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: storeURL, to: backupURL)
            return AppData()
        }
    }

    // MARK: - Save

    /// Debounced, atomic write on a background queue.
    private var pendingWorkItem: DispatchWorkItem?

    func save(_ data: AppData) {
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.writeNow(data)
        }
        pendingWorkItem = work
        queue.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// Forces an immediate write — used when the app is backgrounding.
    ///
    /// Synchronous on purpose. The store is written with complete file
    /// protection, so it becomes unwritable the moment the device locks;
    /// finishing before the scene is suspended is what keeps the last edit.
    func flush(_ data: AppData) {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        queue.sync { [weak self] in
            self?.writeNow(data)
        }
    }

    private func writeNow(_ data: AppData) {
        do {
            let encoded = try encoder.encode(data)
            // The store holds receipts, contacts and prices, so it is written
            // with complete protection: unreadable while the device is locked.
            try encoded.write(to: storeURL, options: [.atomic, .completeFileProtection])
        } catch {
            #if DEBUG
            print("[ProofPath] Save failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Export / Import

    func exportData(_ data: AppData) throws -> URL {
        do {
            let encoded = try encoder.encode(data)
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

    func deleteStore() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        try? FileManager.default.removeItem(at: storeURL)
    }

    private static func exportStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: Date())
    }
}
