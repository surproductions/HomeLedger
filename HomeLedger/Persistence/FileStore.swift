import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum FileStoreError: LocalizedError {
    case unreadableImage
    case unsupportedFormat(String)
    case writeFailed(underlying: Error)
    case missingFile

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "The image could not be read. Try a different photo."
        case .unsupportedFormat(let ext): "Files of type “\(ext)” are not supported. Use a PDF, JPEG, PNG or HEIC file."
        case .writeFailed: "The file could not be saved. Check that your iPhone has free storage and try again."
        case .missingFile: "The original file could not be found on this device."
        }
    }
}

/// Stores photos and documents as individual files under Application Support, protected with
/// iOS Data Protection. Database records reference files by name only.
final class FileStore: @unchecked Sendable {
    static let shared = FileStore()

    let baseURL: URL
    private let fileManager = FileManager.default
    private let thumbnailCache = NSCache<NSString, UIImage>()

    init(baseURL: URL? = nil) {
        if let baseURL {
            self.baseURL = baseURL
        } else {
            let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            self.baseURL = support.appendingPathComponent("HomeLedger/Files", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.baseURL, withIntermediateDirectories: true,
                                          attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        thumbnailCache.countLimit = 200
    }

    func url(for fileName: String) -> URL {
        baseURL.appendingPathComponent(fileName, isDirectory: false)
    }

    func exists(_ fileName: String) -> Bool {
        !fileName.isEmpty && fileManager.fileExists(atPath: url(for: fileName).path)
    }

    @discardableResult
    func save(_ data: Data, fileExtension ext: String, preferredName: String? = nil) throws -> String {
        let name = preferredName ?? "\(UUID().uuidString.lowercased()).\(ext.lowercased())"
        let destination = url(for: name)
        do {
            try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            throw FileStoreError.writeFailed(underlying: error)
        }
        return name
    }

    /// Normalises a photo to JPEG (max 2400 px on the long edge) to keep storage predictable.
    func saveImage(_ image: UIImage, maxDimension: CGFloat = 2400, quality: CGFloat = 0.85) throws -> String {
        let resized = image.resizedToFit(maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: quality) else { throw FileStoreError.unreadableImage }
        return try save(data, fileExtension: "jpg")
    }

    func saveImageData(_ data: Data) throws -> String {
        guard let image = UIImage(data: data) else { throw FileStoreError.unreadableImage }
        return try saveImage(image)
    }

    func data(for fileName: String) -> Data? {
        guard !fileName.isEmpty else { return nil }
        return try? Data(contentsOf: url(for: fileName))
    }

    func fileSize(_ fileName: String) -> Int {
        let attrs = try? fileManager.attributesOfItem(atPath: url(for: fileName).path)
        return (attrs?[.size] as? NSNumber)?.intValue ?? 0
    }

    func delete(_ fileName: String) {
        guard !fileName.isEmpty else { return }
        thumbnailCache.removeObject(forKey: fileName as NSString)
        try? fileManager.removeItem(at: url(for: fileName))
    }

    /// Memory-efficient thumbnail decoding via ImageIO (does not decode the full-size image).
    func thumbnail(for fileName: String, maxPixel: CGFloat = 600) -> UIImage? {
        let key = "\(fileName)#\(Int(maxPixel))" as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let fileURL = url(for: fileName)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    func allFileNames() -> [String] {
        (try? fileManager.contentsOfDirectory(atPath: baseURL.path)) ?? []
    }

    /// Removes files that are no longer referenced by any record. Only called with a complete reference set.
    @discardableResult
    func removeOrphans(referenced: Set<String>) -> Int {
        var removed = 0
        for name in allFileNames() where !referenced.contains(name) && !name.hasPrefix(".") {
            delete(name)
            removed += 1
        }
        return removed
    }

    func deleteAll() {
        thumbnailCache.removeAllObjects()
        for name in allFileNames() { try? fileManager.removeItem(at: url(for: name)) }
    }

    func totalSize() -> Int {
        allFileNames().map(fileSize).reduce(0, +)
    }

    static func contentType(forExtension ext: String) -> StoredContentType? {
        switch ext.lowercased() {
        case "pdf": .pdf
        case "jpg", "jpeg": .jpeg
        case "png": .png
        case "heic", "heif": .heic
        default: nil
        }
    }
}

extension UIImage {
    func resizedToFit(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
