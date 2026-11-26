import Foundation
import PDFKit
import UIKit
import Vision

enum OCRError: LocalizedError {
    case unreadable
    case noText

    var errorDescription: String? {
        switch self {
        case .unreadable: "This file couldn't be read for text. You can still save it and enter details manually."
        case .noText: "No readable text was found. The scan may be blurry, too dark or handwritten — enter details manually."
        }
    }
}

/// On-device text recognition using Apple's Vision framework. Nothing leaves the device.
enum OCRService {
    static let maxPDFPages = 6

    static func recognizeText(in cgImage: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            let observations = request.results ?? []
            return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }

    static func recognizeText(in image: UIImage) async throws -> String {
        guard let cg = image.normalizedCGImage() else { throw OCRError.unreadable }
        return try await recognizeText(in: cg)
    }

    /// Extracts text from a stored file. PDFs with an embedded text layer are read directly;
    /// scanned PDFs are rendered page by page and recognized.
    static func extractText(from url: URL, contentType: StoredContentType) async throws -> String {
        if contentType == .pdf {
            guard let pdf = PDFDocument(url: url) else { throw OCRError.unreadable }
            let embedded = (pdf.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if embedded.count >= 40 { return embedded }
            var parts: [String] = []
            for index in 0..<min(pdf.pageCount, maxPDFPages) {
                guard let page = pdf.page(at: index), let image = render(page: page) else { continue }
                if let text = try? await recognizeText(in: image), !text.isEmpty { parts.append(text) }
            }
            let joined = parts.joined(separator: "\n")
            if joined.isEmpty && embedded.isEmpty { throw OCRError.noText }
            return joined.isEmpty ? embedded : joined
        } else {
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { throw OCRError.unreadable }
            let text = try await recognizeText(in: image)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw OCRError.noText }
            return text
        }
    }

    private static func render(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2.5, 2000 / max(bounds.width, bounds.height))
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        return image.cgImage
    }
}

extension UIImage {
    /// Returns a CGImage with orientation applied, which Vision expects.
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(in: CGRect(origin: .zero, size: size)) }
        return rendered.cgImage
    }
}
