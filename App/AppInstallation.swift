import AppKit

enum AppInstallation {
    static var requiresInstalledCopy: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).path + "/"
        return !path.hasPrefix("/Applications/") && !path.hasPrefix(userApplications)
    }

    static func revealApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
    }
}
