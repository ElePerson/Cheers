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
}
