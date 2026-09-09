import XCTest
import ImageIO
import UIKit
@testable import GetEmDone

@MainActor
final class EvidenceUploadTests: XCTestCase {
    private actor RecordingUploader: EvidenceUploading {
        struct Call: Sendable {
            let data: Data
            let evidenceID: UUID
            let choreID: UUID
        }

        private(set) var calls: [Call] = []
        private var failuresRemaining: Int

        init(failuresRemaining: Int = 0) {
            self.failuresRemaining = failuresRemaining
        }

        func uploadJPEG(_ data: Data, evidenceID: UUID, choreID: UUID, expiresAt: Date) async throws -> EvidenceUploadReceipt {
            calls.append(Call(data: data, evidenceID: evidenceID, choreID: choreID))
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw URLError(.networkConnectionLost)
            }
            return EvidenceUploadReceipt(evidenceID: evidenceID)
        }
    }

    private struct PrefixSanitizer: EvidenceImageSanitizing {
        func sanitizedJPEG(from data: Data) throws -> Data { Data([0xCA, 0xFE]) + data }
    }

    func testSuccessfulUploadOnlyMarksPhotoReadyAfterServerAcceptsSanitizedBytes() async {
        let uploader = RecordingUploader()
        let chore = Chore(title: "Bed", detail: "", evidence: .photo)
        let store = HouseholdStore(
            role: .child,
            childName: "Test",
            chores: [chore],
            devices: [],
            evidenceUploader: uploader,
            imageSanitizer: PrefixSanitizer()
        )

        await store.uploadPhoto(Data([0x01]), for: chore)

        guard case .uploaded = store.evidenceUploadState(for: chore) else {
            return XCTFail("Expected completed upload")
        }
        XCTAssertEqual(store.chores[0].evidenceProgress, .photoReady)
        let calls = await uploader.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].data, Data([0xCA, 0xFE, 0x01]))
        XCTAssertEqual(calls[0].choreID, chore.id)
    }

    func testFailedUploadKeepsChoreIncompleteAndRetryReusesEvidenceID() async {
        let uploader = RecordingUploader(failuresRemaining: 1)
        let chore = Chore(title: "Bed", detail: "", evidence: .photo)
        let store = HouseholdStore(
            role: .child,
            childName: "Test",
            chores: [chore],
            devices: [],
            evidenceUploader: uploader,
            imageSanitizer: PrefixSanitizer()
        )

        await store.uploadPhoto(Data([0x01]), for: chore)
        guard case .failed = store.evidenceUploadState(for: chore) else {
            return XCTFail("Expected retryable failure")
        }
        XCTAssertFalse(store.chores[0].canSubmit)

        await store.retryPhotoUpload(for: chore)

        guard case .uploaded = store.evidenceUploadState(for: chore) else {
            return XCTFail("Expected retry to complete")
        }
        let calls = await uploader.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].evidenceID, calls[1].evidenceID)
    }

    func testImageSanitizerDropsGPSAndEXIFMetadata() throws {
        let source = try jpegWithPrivateMetadata()
        let sanitized = try MetadataStrippingImageSanitizer().sanitizedJPEG(from: source)
        guard let imageSource = CGImageSourceCreateWithData(sanitized as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return XCTFail("Expected readable sanitized JPEG")
        }
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment])
        XCTAssertNil(tiff?[kCGImagePropertyTIFFMake])
    }

    private func jpegWithPrivateMetadata() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        guard let cgImage = image.cgImage else { throw EvidenceUploadError.imageEncodingFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
            throw EvidenceUploadError.imageEncodingFailed
        }
        let metadata: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 40.0, kCGImagePropertyGPSLongitude: -105.0],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "child bedroom"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Private Camera"]
        ]
        CGImageDestinationAddImage(destination, cgImage, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EvidenceUploadError.imageEncodingFailed }
        return data as Data
    }
}
