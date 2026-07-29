import XCTest
@testable import Cheers

final class ReleaseReadinessTests: XCTestCase {
    func testProductionServerIdentity() {
        let identity = ServerIdentity.resolve("https://www.tocheers.com/api/v1")

        XCTAssertEqual(identity.kind, .production)
        XCTAssertEqual(identity.title, "Cheers Cloud")
        XCTAssertTrue(identity.isProduction)
    }

    func testCustomServerIdentityExposesHost() {
        let identity = ServerIdentity.resolve("http://localhost:30080/api/v1")

        XCTAssertEqual(identity.kind, .custom)
        XCTAssertEqual(identity.title, "Custom workspace")
        XCTAssertEqual(identity.detail, "localhost")
        XCTAssertFalse(identity.isProduction)
    }

    func testDMUsesPeerNameInsteadOfGenericChannelName() throws {
        let data = Data("""
        {
          "channel_id":"dm-1",
          "workspace_id":null,
          "name":"Direct Message",
          "type":"dm",
          "peer_name":"Ada Lovelace"
        }
        """.utf8)

        let channel = try JSONDecoder().decode(ChannelDto.self, from: data)

        XCTAssertEqual(channel.displayName, "Ada Lovelace")
    }

    func testDMWithoutPeerNeverShowsGenericDirectMessageLabel() throws {
        let data = Data("""
        {
          "channel_id":"dm-2",
          "workspace_id":null,
          "name":"Direct Message",
          "type":"dm"
        }
        """.utf8)

        let channel = try JSONDecoder().decode(ChannelDto.self, from: data)

        XCTAssertEqual(channel.displayName, "Unknown participant")
    }

    func testApprovalUsesClaudeRawInputAndLocations() throws {
        let request = try permissionRequest("""
        {
          "request_id":"permission-1",
          "title":"ACP permission request",
          "tool": {
            "kind":"edit",
            "title":"Edit release metadata",
            "raw_input":{"file_path":"/repo/Info.plist","content":"1.0.0"},
            "locations":[{"path":"/repo/Info.plist"}]
          },
          "options":[{"option_id":"allow_once","kind":"allow_once"}]
        }
        """)

        XCTAssertEqual(request.title, "Edit release metadata")
        XCTAssertEqual(request.command, "/repo/Info.plist  (5 chars)")
        XCTAssertEqual(request.locations, ["/repo/Info.plist"])
    }

    func testApprovalUsesCursorLocationsWhenCommandIsMissing() throws {
        let request = try permissionRequest("""
        {
          "request_id":"permission-2",
          "tool": {
            "kind":"edit",
            "locations":[{"path":"/repo/Sources/App.swift"}]
          }
        }
        """)

        XCTAssertEqual(request.title, "Approval needed")
        XCTAssertEqual(request.command, "/repo/Sources/App.swift")
        XCTAssertEqual(request.locations, ["/repo/Sources/App.swift"])
    }

    func testApprovalUsesCodexArgvPreview() throws {
        let request = try permissionRequest("""
        {
          "request_id":"permission-3",
          "tool":{"raw_input":{"argv":["xcodebuild","test"]}}
        }
        """)

        XCTAssertEqual(request.command, "xcodebuild test")
    }

    func testAttachmentUploadPolicyRejectsEmptyAndOversizedFiles() {
        XCTAssertThrowsError(try AttachmentUploadPolicy.validate(byteCount: 0)) { error in
            XCTAssertEqual(error as? AttachmentUploadError, .empty)
        }
        XCTAssertNoThrow(try AttachmentUploadPolicy.validate(
            byteCount: AttachmentUploadPolicy.maximumByteCount
        ))
        XCTAssertThrowsError(try AttachmentUploadPolicy.validate(
            byteCount: AttachmentUploadPolicy.maximumByteCount + 1
        ))
    }

    func testImageAttachmentDetectionUsesMimeTypeAndSafeExtensionFallback() throws {
        let mimeImage = try fileRef(filename: "opaque.bin", contentType: "image/webp")
        let extensionImage = try fileRef(filename: "photo.HEIC", contentType: nil)
        let document = try fileRef(filename: "report.pdf", contentType: "application/pdf")

        XCTAssertTrue(mimeImage.isImageAttachment)
        XCTAssertTrue(extensionImage.isImageAttachment)
        XCTAssertFalse(document.isImageAttachment)
    }

    private func permissionRequest(_ json: String) throws -> PermissionRequest {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        return try XCTUnwrap(PermissionRequest(contentData: value))
    }

    private func fileRef(filename: String, contentType: String?) throws -> MessageFileRef {
        var object: [String: Any] = [
            "file_id": UUID().uuidString,
            "original_filename": filename,
        ]
        if let contentType { object["content_type"] = contentType }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(MessageFileRef.self, from: data)
    }
}
