//
//  AttachmentStore.swift
//  ProofOfPath
//
//  Files the user attaches live next to the JSON store, referenced by file name.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum AttachmentError: LocalizedError {
    case copyFailed(String)
    case tooLarge(Int64)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .copyFailed(let detail): return "The file could not be attached. \(detail)"
        case .tooLarge(let bytes): return "This file is \(POPFormat.fileSize(bytes)). The limit is 25 MB."
        case .unreadable: return "The file could not be read. It may have been moved or deleted."
        }
    }
}

final class AttachmentStore {

    static let shared = AttachmentStore()

    static let maxBytes: Int64 = 25 * 1024 * 1024

    private var rootURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Attachments", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    /// File names come from the stored JSON, which the user can replace via
    /// Import Backup. A crafted name like `../../proofpath-data.json` would
    /// otherwise let a hostile file reach outside the attachments folder, so
    /// every name is reduced to a bare component and the result is verified to
    /// still sit inside the attachments directory.
    private func safeURL(for fileName: String) -> URL? {
        let component = (fileName as NSString).lastPathComponent
        guard !component.isEmpty,
              component != ".",
              component != "..",
              !component.contains("/"),
              !component.contains("\\")
        else { return nil }

        let candidate = rootURL.appendingPathComponent(component)
        let root = rootURL.standardizedFileURL.path
        let resolved = candidate.standardizedFileURL.path
        guard resolved.hasPrefix(root.hasSuffix("/") ? root : root + "/") else { return nil }
        return candidate
    }

    /// Non-optional accessor for call sites that only need a path to hand to a
    /// previewer. An unsafe name resolves to a file that cannot exist.
    func url(for fileName: String) -> URL {
        safeURL(for: fileName) ?? rootURL.appendingPathComponent("invalid-\(UUID().uuidString)")
    }

    func exists(_ fileName: String?) -> Bool {
        guard let fileName, let url = safeURL(for: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Import

    /// Copies a security-scoped file into the app's own storage.
    func importFile(from sourceURL: URL) throws -> EvidenceAttachment {
        var needsRelease = false
        if sourceURL.startAccessingSecurityScopedResource() { needsRelease = true }
        defer { if needsRelease { sourceURL.stopAccessingSecurityScopedResource() } }

        let values = try? sourceURL.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values?.fileSize ?? 0)
        if size > Self.maxBytes { throw AttachmentError.tooLarge(size) }

        let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension.lowercased()
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = url(for: fileName)

        do {
            let data = try Data(contentsOf: sourceURL)
            guard !data.isEmpty else { throw AttachmentError.unreadable }
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
            return EvidenceAttachment(
                fileName: fileName,
                originalName: (sourceURL.lastPathComponent as NSString).lastPathComponent,
                byteSize: Int64(data.count),
                isImage: Self.imageExtensions.contains(ext)
            )
        } catch let error as AttachmentError {
            throw error
        } catch {
            throw AttachmentError.copyFailed(error.localizedDescription)
        }
    }

    /// Stores raw image data (from the photo picker).
    func importImageData(_ data: Data, suggestedName: String = "Photo") throws -> EvidenceAttachment {
        guard !data.isEmpty else { throw AttachmentError.unreadable }
        let size = Int64(data.count)
        if size > Self.maxBytes { throw AttachmentError.tooLarge(size) }

        let fileName = "\(UUID().uuidString).jpg"
        let destination = url(for: fileName)
        do {
            try data.write(to: destination, options: [.atomic, .completeFileProtection])
            return EvidenceAttachment(
                fileName: fileName,
                originalName: suggestedName,
                byteSize: size,
                isImage: true
            )
        } catch {
            throw AttachmentError.copyFailed(error.localizedDescription)
        }
    }

    #if canImport(UIKit)
    func loadImage(named fileName: String?) -> UIImage? {
        guard let fileName, exists(fileName), let source = safeURL(for: fileName) else { return nil }
        return UIImage(contentsOfFile: source.path)
    }
    #endif

    func data(for fileName: String) -> Data? {
        guard exists(fileName), let source = safeURL(for: fileName) else { return nil }
        return try? Data(contentsOf: source)
    }

    // MARK: - Delete

    func delete(_ fileNames: [String]) {
        for name in fileNames where !name.isEmpty {
            guard let target = safeURL(for: name) else { continue }
            try? FileManager.default.removeItem(at: target)
        }
    }

    func deleteAll() {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Total bytes used by attachments — shown in Settings.
    func totalUsedBytes() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return contents.reduce(0) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return partial + Int64(size)
        }
    }

    func fileCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: rootURL.path))?.count ?? 0
    }

    /// Removes attachment files that nothing references any more.
    @discardableResult
    func pruneOrphans(referenced: Set<String>) -> Int {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: rootURL.path) else { return 0 }
        let referencedNames = Set(referenced.map { ($0 as NSString).lastPathComponent })
        var removed = 0
        for name in contents where !referencedNames.contains(name) {
            try? FileManager.default.removeItem(at: url(for: name))
            removed += 1
        }
        return removed
    }

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "bmp"]
}
