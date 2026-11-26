import Foundation
import UIKit
import UniformTypeIdentifiers

/// A file that has been copied into HomeLedger's storage but not yet saved as a record.
/// If the user cancels the review, `discard()` removes the copy so nothing is orphaned.
struct ImportedFile: Identifiable, Equatable {
    let id = UUID()
    let fileName: String
    let originalFileName: String
    let contentType: StoredContentType
    let fileSize: Int

    func discard(store: FileStore = .shared) { store.delete(fileName) }
}

enum DocumentImporter {
    static let maxFileSize = 50 * 1024 * 1024
    static let supportedTypes: [UTType] = [.pdf, .jpeg, .png, .heic, .image]

    /// Copies a security-scoped file from the Files app into app storage.
    static func importFile(at url: URL, store: FileStore = .shared) throws -> ImportedFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var result: Result<ImportedFile, Error> = .failure(FileStoreError.missingFile)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            result = Result { try importData(at: readURL, originalName: url.lastPathComponent, store: store) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private static func importData(at url: URL, originalName: String, store: FileStore) throws -> ImportedFile {
        let ext = url.pathExtension.lowercased()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize, size > maxFileSize {
            throw FileStoreError.writeFailed(underlying: NSError(domain: "HomeLedger", code: 1, userInfo: [NSLocalizedDescriptionKey: "File is larger than 50 MB"]))
        }
        let data = try Data(contentsOf: url)
        guard let type = FileStore.contentType(forExtension: ext) ?? sniff(data) else {
            throw FileStoreError.unsupportedFormat(ext.isEmpty ? "unknown" : ext)
        }
        if type == .heic {
            // Convert HEIC to JPEG for compatibility with PDF reports and other apps.
            guard let image = UIImage(data: data) else { throw FileStoreError.unreadableImage }
            let name = try store.saveImage(image)
            return ImportedFile(fileName: name, originalFileName: originalName, contentType: .jpeg, fileSize: store.fileSize(name))
        }
        let name = try store.save(data, fileExtension: type.fileExtension)
        return ImportedFile(fileName: name, originalFileName: originalName, contentType: type, fileSize: data.count)
    }

    static func importImage(_ image: UIImage, originalName: String = "Photo.jpg", store: FileStore = .shared) throws -> ImportedFile {
        let name = try store.saveImage(image)
        return ImportedFile(fileName: name, originalFileName: originalName, contentType: .jpeg, fileSize: store.fileSize(name))
    }

    static func importImageData(_ data: Data, store: FileStore = .shared) throws -> ImportedFile {
        guard let image = UIImage(data: data) else { throw FileStoreError.unreadableImage }
        return try importImage(image, store: store)
    }

    /// Combines document-camera pages into a single PDF, preserving every page.
    static func importScannedPages(_ pages: [UIImage], store: FileStore = .shared) throws -> ImportedFile {
        guard !pages.isEmpty else { throw FileStoreError.unreadableImage }
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: pageRect).pdfData { ctx in
            for page in pages {
                ctx.beginPage()
                let img = page.resizedToFit(maxDimension: 2000)
                let scale = min(pageRect.width / img.size.width, pageRect.height / img.size.height)
                let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
                img.draw(in: CGRect(x: (pageRect.width - size.width) / 2, y: (pageRect.height - size.height) / 2, width: size.width, height: size.height))
            }
        }
        let name = try store.save(data, fileExtension: "pdf")
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        return ImportedFile(fileName: name, originalFileName: "Scan \(stamp).pdf", contentType: .pdf, fileSize: data.count)
    }

    static func sniff(_ data: Data) -> StoredContentType? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if bytes.count >= 12, String(bytes: bytes[4..<12], encoding: .ascii)?.hasPrefix("ftyphei") == true { return .heic }
        return nil
    }
}
