import Foundation

@main
enum UpdateCheckerTests {
    static func main() throws {
        let json = """
        {"tag_name":"v1.1","html_url":"https://github.com/theodor-ubp/sysdash/releases/tag/v1.1",
         "assets":[
          {"name":"up-sysdash-v1.1.dmg.sha256","browser_download_url":"https://github.com/theodor-ubp/sysdash/releases/download/v1.1/up-sysdash-v1.1.dmg.sha256"},
          {"name":"source.zip","browser_download_url":"https://github.com/theodor-ubp/sysdash/releases/download/v1.1/source.zip"},
          {"name":"up-sysdash-v1.1.dmg","browser_download_url":"https://github.com/theodor-ubp/sysdash/releases/download/v1.1/up-sysdash-v1.1.dmg"}]}
        """
        let decoder = JSONDecoder()
        let release = try decoder.decode(GitHubRelease.self, from: Data(json.utf8))
        precondition(release.version == "1.1")
        precondition(release.version.compare("1.0", options: .numeric) == .orderedDescending)
        precondition(release.downloadURL?.lastPathComponent == "up-sysdash-v1.1.dmg")
        precondition(release.downloadURL?.absoluteString != release.htmlUrl)
        let noDMG = json.replacingOccurrences(of: "up-sysdash-v1.1.dmg\"", with: "up-sysdash-v1.1.txt\"")
        let unavailable = try decoder.decode(GitHubRelease.self, from: Data(noDMG.utf8))
        precondition(unavailable.downloadURL == nil)
        let insecure = json.replacingOccurrences(of: "https://github.com", with: "http://github.com")
        let insecureRelease = try decoder.decode(GitHubRelease.self, from: Data(insecure.utf8))
        precondition(insecureRelease.downloadURL == nil)
        print("PASS: release tag comparison, direct DMG selection, checksum/archive filtering, missing installer and HTTPS requirement")

        if CommandLine.arguments.count > 1 {
            let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let published = try decoder.decode(GitHubRelease.self, from: data)
            // Exactly the fields and comparison used by installed v1.0 clients.
            struct LegacyRelease: Decodable {
                let tagName: String
                let htmlUrl: String
                enum CodingKeys: String, CodingKey {
                    case tagName = "tag_name"
                    case htmlUrl = "html_url"
                }
            }
            let legacy = try decoder.decode(LegacyRelease.self, from: data)
            let latest = legacy.tagName.drop(while: { $0 == "v" }).description
            precondition(latest.compare("1.0", options: .numeric) == .orderedDescending)
            precondition(latest.compare("1.1", options: .numeric) == .orderedDescending)
            precondition(latest.compare("1.2", options: .numeric) == .orderedDescending)
            precondition(published.tagName == "v1.3")
            precondition(published.downloadURL?.lastPathComponent == "up-sysdash-v1.3.dmg")
            precondition(published.version.compare("1.3", options: .numeric) == .orderedSame)
            print("PASS: published GitHub latest response is detected by v1.0/v1.1/v1.2 and supplies the direct v1.3 DMG; v1.3 is current")
        }
    }
}
