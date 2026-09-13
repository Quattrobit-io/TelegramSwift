import Foundation
import Darwin
import XCTest
@testable import ApiCredentials

final class ConfigurationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        directory = package.appendingPathComponent("../../work/configuration-tests/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func load(_ json: String) throws -> TelegramApplicationCredentials {
        let url = directory.appendingPathComponent("application.json")
        try Data(json.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return try TelegramApplicationCredentials.load(from: url)
    }

    func testOwnApplicationCredentials() throws {
        let credentials = try load("""
            {"api_id":2147483647,"api_hash":"0123456789abcdef0123456789ABCDEF"}
            """)
        XCTAssertEqual(credentials.apiId, 2147483647)
        XCTAssertEqual(credentials.apiHash, "0123456789abcdef0123456789ABCDEF")
    }

    func testAbsentFileIsExplicit() {
        XCTAssertThrowsError(try TelegramApplicationCredentials.load(
            from: directory.appendingPathComponent("missing.json"))) {
            XCTAssertEqual($0 as? TelegramApplicationCredentials.ConfigurationError, .missingFile)
        }
    }

    func testNonRegularAndOversizedConfigurationAreRejected() throws {
        let fifo = directory.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertThrowsError(try TelegramApplicationCredentials.load(from: fifo))
        XCTAssertThrowsError(try load(String(repeating: "x", count: 4097)))
        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: directory.appendingPathComponent("application.json"))
        XCTAssertThrowsError(try TelegramApplicationCredentials.load(from: link))
    }

    func testParentDirectoryLinkIsRejectedBeforeReadingCredentials() throws {
        _ = try load("{\"api_id\":2147483647,\"api_hash\":\"0123456789abcdef0123456789abcdef\"}")
        let namespace = directory.appendingPathComponent("namespace")
        try FileManager.default.createDirectory(at: namespace, withIntermediateDirectories: false)
        let link = namespace.appendingPathComponent("Telegram")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        XCTAssertThrowsError(try TelegramApplicationCredentials.load(
            from: link.appendingPathComponent("application.json"))) {
            XCTAssertEqual($0 as? TelegramApplicationCredentials.ConfigurationError, .unsafeStorage)
        }
    }

    func testStorageRejectsSymbolicLinksAndNonprivateDirectories() throws {
        let target = directory.appendingPathComponent("existing-profile")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let root = directory.appendingPathComponent("Octron/Telegram")
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: target)
        XCTAssertThrowsError(try ApiEnvironment.prepareStorageDirectory(at: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("account-data").path))
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let accountData = root.appendingPathComponent("account-data")
        try FileManager.default.createSymbolicLink(at: accountData, withDestinationURL: target)
        XCTAssertThrowsError(try ApiEnvironment.prepareStorageDirectory(at: root))
        try FileManager.default.removeItem(at: accountData)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        XCTAssertThrowsError(try ApiEnvironment.prepareStorageDirectory(at: root))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try ApiEnvironment.prepareStorageDirectory(at: root)
        let attributes = try FileManager.default.attributesOfItem(atPath: accountData.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testInvalidAndUpstreamCredentialsAreRejected() {
        for id in [0, -1, 9] {
            XCTAssertThrowsError(try load("""
                {"api_id":\(id),"api_hash":"0123456789abcdef0123456789abcdef"}
                """)) {
                XCTAssertEqual($0 as? TelegramApplicationCredentials.ConfigurationError, .invalidCredentials)
            }
        }
        for hash in ["", "0123", String(repeating: "z", count: 32)] {
            XCTAssertThrowsError(try load("""
                {"api_id":2147483647,"api_hash":"\(hash)"}
                """)) {
                XCTAssertEqual($0 as? TelegramApplicationCredentials.ConfigurationError, .invalidCredentials)
            }
        }
    }

    func testMalformedOrWrongTypesAreRejectedWithoutEchoingInput() {
        let input = "PRIVATE_INVALID_VALUE"
        for json in [input, "{}", "{\"api_id\":\"\(input)\"}",
                     "{\"api_id\":2147483648,\"api_hash\":\"0123456789abcdef0123456789abcdef\"}"] {
            XCTAssertThrowsError(try load(json)) {
                XCTAssertEqual($0 as? TelegramApplicationCredentials.ConfigurationError, .invalidFormat)
                XCTAssertFalse($0.localizedDescription.contains(input))
            }
        }
    }
}
