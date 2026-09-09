import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum EvidenceUploadState: Equatable, Sendable {
    case idle
    case preparing
    case uploading
    case uploaded(evidenceID: UUID)
    case failed(message: String)

    var isBusy: Bool {
        self == .preparing || self == .uploading
    }
}

struct EvidenceUploadReceipt: Equatable, Sendable {
    let evidenceID: UUID
}

protocol EvidenceUploading: Sendable {
    func uploadJPEG(
        _ data: Data,
        evidenceID: UUID,
        choreID: UUID,
        expiresAt: Date
    ) async throws -> EvidenceUploadReceipt
}

protocol EvidenceImageSanitizing: Sendable {
    func sanitizedJPEG(from data: Data) throws -> Data
}

enum EvidenceUploadError: LocalizedError, Equatable {
    case invalidImage
    case imageEncodingFailed
    case notConfigured
    case rejected

    var errorDescription: String? {
        switch self {
        case .invalidImage: "That photo couldn't be opened. Please choose another one."
        case .imageEncodingFailed: "That photo couldn't be prepared safely. Please try another one."
        case .notConfigured: "Photo sharing isn't connected yet. Ask a parent to check setup."
        case .rejected: "The photo couldn't be uploaded. Check your connection and try again."
        }
    }
}

/// Decodes pixels and creates a new JPEG without copying source metadata. The
/// source container (including EXIF, GPS, captions, and the original filename)
/// is never sent to the evidence service.
struct MetadataStrippingImageSanitizer: EvidenceImageSanitizing {
    func sanitizedJPEG(from data: Data) throws -> Data {
        guard let image = UIImage(data: data), let cgImage = normalizedCGImage(from: image) else {
            throw EvidenceUploadError.invalidImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { throw EvidenceUploadError.imageEncodingFailed }

        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.82,
            kCGImagePropertyOrientation: 1
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw EvidenceUploadError.imageEncodingFailed
        }
        return output as Data
    }

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return rendered.cgImage
    }
}

struct EvidenceAPIConfiguration: Sendable {
    let baseURL: URL
    let childMemberID: String
    let bearerToken: String

    static var development: EvidenceAPIConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        guard let rawURL = environment["GETEMDONE_API_URL"],
              let baseURL = URL(string: rawURL),
              baseURL.scheme == "https" || environment["GETEMDONE_ALLOW_INSECURE_LOCALHOST"] == "1",
              let childMemberID = environment["GETEMDONE_CHILD_MEMBER_ID"],
              let bearerToken = environment["GETEMDONE_BEARER_TOKEN"],
              !bearerToken.isEmpty else { return nil }
        return EvidenceAPIConfiguration(
            baseURL: baseURL,
            childMemberID: childMemberID,
            bearerToken: bearerToken
        )
    }
}

struct EvidenceAPIClient: EvidenceUploading {
    private struct UploadBody: Encodable {
        let childMemberId: String
        let contentType: String
        let base64: String
        let expiresAt: Date
    }

    let configuration: EvidenceAPIConfiguration?
    var session: URLSession = .shared

    func uploadJPEG(_ data: Data, evidenceID: UUID, choreID: UUID, expiresAt: Date) async throws -> EvidenceUploadReceipt {
        guard let configuration else { throw EvidenceUploadError.notConfigured }
        var request = URLRequest(url: configuration.baseURL
            .appending(path: "v1/evidence")
            .appending(path: evidenceID.uuidString.lowercased()))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(evidenceID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.setValue("Bearer \(configuration.bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.evidence.encode(UploadBody(
            childMemberId: configuration.childMemberID,
            contentType: "image/jpeg",
            base64: data.base64EncodedString(),
            expiresAt: expiresAt
        ))

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EvidenceUploadError.rejected
        }
        return EvidenceUploadReceipt(evidenceID: evidenceID)
    }
}

private extension JSONEncoder {
    static var evidence: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
