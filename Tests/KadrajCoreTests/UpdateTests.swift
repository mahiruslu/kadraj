import Foundation
import Testing
@testable import KadrajCore

@Test func versionOrdering() throws {
    let v = { (s: String) in try #require(SemanticVersion(s)) }
    #expect(try v("1.10.0") > v("1.9.2"))
    #expect(try v("v1.2.0") == v("1.2.0"))
    #expect(try v("1.2.0") > v("1.2.0-beta.1"))
    #expect(try v("0.0.0-nightly.ab12") < v("0.1.0"))
    #expect(try v("1.2") == v("1.2.0"))
    #expect(SemanticVersion("abc") == nil)
    #expect(try v("0.0.0-dev").isDevelopment)
    #expect(try v("0.0.0-nightly.ab12").isDevelopment)
    #expect(try !v("1.2.0").isDevelopment)
}

private let sample = #"""
{"tag_name":"v1.2.0","name":"Kadraj 1.2.0","draft":false,"prerelease":false,
 "assets":[{"name":"Kadraj.zip.sha256","browser_download_url":"https://github.com/mahiruslu/kadraj/releases/download/v1.2.0/Kadraj.zip.sha256"},
           {"name":"Kadraj.zip","browser_download_url":"https://github.com/mahiruslu/kadraj/releases/download/v1.2.0/Kadraj.zip"}]}
"""#

@Test func parsesLatestRelease() throws {
    let info = try #require(ReleaseInfo.parse(Data(sample.utf8)))
    #expect(info.version == SemanticVersion("1.2.0"))
    #expect(info.zipURL.lastPathComponent == "Kadraj.zip")
    #expect(info.checksumURL.lastPathComponent == "Kadraj.zip.sha256")
}

@Test func releaseWithoutAssetsIsRejected() {
    #expect(ReleaseInfo.parse(Data(#"{"tag_name":"v1.0.0","assets":[]}"#.utf8)) == nil)
    #expect(ReleaseInfo.parse(Data("not json".utf8)) == nil)
}

@Test func checksumFileParsing() {
    #expect(ReleaseInfo.expectedChecksum(from: "abc123  Kadraj.zip\n") == "abc123")
    #expect(ReleaseInfo.expectedChecksum(from: "") == nil)
}

@Test func strictVersionParsing() throws {
    #expect(SemanticVersion("1..2") == nil)
    #expect(SemanticVersion("-1.2.3") == nil)
    #expect(SemanticVersion("+1.2.3") == nil)
    #expect(SemanticVersion("1.-2.3") == nil)
    #expect(SemanticVersion("1.2.3+build.5") == SemanticVersion("1.2.3"))
    #expect(SemanticVersion("1.0.0-beta.01") == SemanticVersion("1.0.0-beta.1"))
    let v = { (s: String) in try #require(SemanticVersion(s)) }
    #expect(try v("1.0.0-beta.2") < v("1.0.0-beta.10"))
    #expect(try v("1.0.0-alpha") < v("1.0.0-beta"))
    #expect(try v("1.0.0-1") < v("1.0.0-alpha"))
}

@Test func releaseAssetURLsMustBeThisRepository() {
    let evil = #"""
    {"tag_name":"v1.2.0","assets":[{"name":"Kadraj.zip","browser_download_url":"file:///etc/passwd"},
     {"name":"Kadraj.zip.sha256","browser_download_url":"https://github.com/mahiruslu/kadraj/releases/download/v1.2.0/Kadraj.zip.sha256"}]}
    """#
    #expect(ReleaseInfo.parse(Data(evil.utf8)) == nil)
    let otherRepo = sample.replacingOccurrences(of: "mahiruslu/kadraj", with: "attacker/kadraj")
    #expect(ReleaseInfo.parse(Data(otherRepo.utf8)) == nil)
    let otherTag = sample.replacingOccurrences(of: "download/v1.2.0/", with: "download/v0.9.0/")
    #expect(ReleaseInfo.parse(Data(otherTag.utf8)) == nil)
}
