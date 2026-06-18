import Foundation
import AppKit

final class UpdateChecker {
    static let shared = UpdateChecker()
    private init() {}

    private let repoOwner = "theodor-ubp"
    private let repoName  = "sysdash"

    func checkForUpdates(showIfUpToDate: Bool = false) {
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            guard let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = try? JSONDecoder().decode(GitHubRelease.self, from: data)
            else {
                if showIfUpToDate {
                    DispatchQueue.main.async { self.showNetworkError() }
                }
                return
            }

            let latest  = release.tagName.drop(while: { $0 == "v" }).description
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            let isNewer = latest.compare(current, options: .numeric) == .orderedDescending

            DispatchQueue.main.async {
                if isNewer {
                    self.showUpdateAvailable(version: latest, releaseURL: release.htmlUrl)
                } else if showIfUpToDate {
                    self.showUpToDate(current: current)
                }
            }
        }.resume()
    }

    // MARK: - Alerts

    private func showUpdateAvailable(version: String, releaseURL: String) {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let alert = NSAlert()
        alert.messageText = "UP Sysdash \(version) is Available"
        alert.informativeText = "You have version \(current). Would you like to download the update?"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn,
           let u = URL(string: releaseURL) {
            NSWorkspace.shared.open(u)
        }
    }

    private func showUpToDate(current: String) {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "UP Sysdash \(current) is the latest version."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showNetworkError() {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not reach GitHub. Check your internet connection and try again."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - GitHub API model

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
    }
}
