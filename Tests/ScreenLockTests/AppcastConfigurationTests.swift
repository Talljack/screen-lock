import XCTest

final class AppcastConfigurationTests: XCTestCase {
    func testInfoPlistUsesReleaseAssetFeedURL() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoPlistURL = repoRoot.appendingPathComponent("ScreenLock/App/Info.plist")

        let data = try Data(contentsOf: infoPlistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let feedURL = try XCTUnwrap(plist["SUFeedURL"] as? String)

        XCTAssertEqual(
            feedURL,
            "https://raw.githubusercontent.com/Talljack/screen-lock/main/appcast.xml"
        )
    }
}
