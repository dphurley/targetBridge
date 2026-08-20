import Foundation
import XCTest
@testable import TargetBridge

final class TBVRReceiverServiceTests: XCTestCase {
    func testHealthEndpointStartsOnLocalhost() async throws {
        let receiver = TBVRReceiverService()
        receiver.start(inputHandler: { _ in }, requiresMacPermissions: false)
        defer { receiver.stop() }

        try await Task.sleep(for: .milliseconds(250))
        let unpairedURL = try XCTUnwrap(URL(string: "http://127.0.0.1:51239/health"))
        let (_, unpairedResponse) = try await URLSession.shared.data(from: unpairedURL)
        XCTAssertEqual((unpairedResponse as? HTTPURLResponse)?.statusCode, 403)

        let paired = try XCTUnwrap(URL(string: receiver.browserURL))
        let pairingQuery = paired.query ?? ""
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:51239/health?\(pairingQuery)"))
        let (data, response) = try await URLSession.shared.data(from: url)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "{\"status\":\"ok\"}")
    }
}
