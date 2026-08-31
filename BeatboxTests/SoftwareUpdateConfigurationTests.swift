import Foundation
import Testing

@Suite("Sparkle configuration")
struct SoftwareUpdateConfigurationTests {
    @Test("Hosted app contains a secure GitHub appcast configuration")
    func appcastConfiguration() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let feedURLString = try #require(info["SUFeedURL"] as? String)
        let feedURL = try #require(URL(string: feedURLString))
        let publicKey = try #require(info["SUPublicEDKey"] as? String)
        let decodedPublicKey = try #require(Data(base64Encoded: publicKey))

        #expect(feedURL.scheme == "https")
        #expect(feedURL.host == "github.com")
        #expect(feedURL.path.hasPrefix("/cnodon/Beatbox/"))
        #expect(feedURL.path.hasSuffix("/releases/latest/download/appcast.xml"))
        #expect(decodedPublicKey.count == 32)
        #expect(info["SUEnableInstallerLauncherService"] as? Bool == true)
        #expect(info["SUEnableDownloaderService"] == nil)
    }
}
