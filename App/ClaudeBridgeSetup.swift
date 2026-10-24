import Foundation

/// Setup is explicit and reversible. It never executes or overwrites another status-line command.
enum ClaudeBridgeSetup {
    static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    private struct Backup: Codable {
        let version: Int
        let originalSettings: Data?
        let installedCommand: String
    }

    static func install(executableURL: URL, settingsURL: URL = defaultSettingsURL,
                        backupURL: URL? = nil) throws {
        guard executableURL.isFileURL, !executableURL.path.contains("\0"),
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ClaudeBridgeError.invalidData
        }
        let backupURL = backupURL ?? defaultBackupURL(for: settingsURL)
        let command = shellQuote(executableURL.path) + " --claude-statusline-bridge"
        try ClaudeBridgeFiles.withLock(for: settingsURL) {
            let currentData = try ClaudeBridgeFiles.readIfPresent(settingsURL, maximumBytes: ClaudeStatuslineParser.maximumInputBytes)
            var settings = try settingsObject(currentData)
            let backupData = try ClaudeBridgeFiles.readIfPresent(backupURL, maximumBytes: 2_097_152)
            let priorBackup = try backupData.map { try JSONDecoder().decode(Backup.self, from: $0) }
            if let priorBackup {
                guard priorBackup.installedCommand == command else { throw ClaudeBridgeError.bridgePathChanged }
                guard priorBackup.version == 1,
                      isOurStatusLine(settings["statusLine"], command: priorBackup.installedCommand)
                        || currentData == priorBackup.originalSettings else { throw ClaudeBridgeError.changedConfiguration }
                if isOurStatusLine(settings["statusLine"], command: command) { return }
            } else if settings["statusLine"] != nil {
                throw ClaudeBridgeError.existingStatusLine
            }
            let originalData: Data?
            if let priorBackup { originalData = priorBackup.originalSettings }
            else { originalData = currentData }
            let backup = Backup(version: 1, originalSettings: originalData,
                                installedCommand: command)
            // Persist the full original file before the first settings mutation.
            try ClaudeBridgeFiles.write(JSONEncoder().encode(backup), to: backupURL)
            settings["statusLine"] = ["type": "command", "command": command]
            try ClaudeBridgeFiles.write(JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]),
                                        to: settingsURL)
        }
    }

    static func remove(settingsURL: URL = defaultSettingsURL, backupURL: URL? = nil) throws {
        let backupURL = backupURL ?? defaultBackupURL(for: settingsURL)
        try ClaudeBridgeFiles.withLock(for: settingsURL) {
            guard let backupData = try ClaudeBridgeFiles.readIfPresent(backupURL, maximumBytes: 2_097_152),
                  let backup = try? JSONDecoder().decode(Backup.self, from: backupData), backup.version == 1 else {
                throw ClaudeBridgeError.missingBackup
            }
            let currentData = try ClaudeBridgeFiles.readIfPresent(settingsURL, maximumBytes: ClaudeStatuslineParser.maximumInputBytes)
            if currentData == backup.originalSettings {
                // Recover an interrupted first install that wrote its backup only.
                try FileManager.default.removeItem(at: backupURL)
                return
            }
            var settings = try settingsObject(currentData)
            guard isOurStatusLine(settings["statusLine"], command: backup.installedCommand) else {
                throw ClaudeBridgeError.changedConfiguration
            }
            let original = try settingsObject(backup.originalSettings)
            settings["statusLine"] = original["statusLine"]
            try ClaudeBridgeFiles.write(JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]),
                                        to: settingsURL)
            try FileManager.default.removeItem(at: backupURL)
        }
    }

    private static func defaultBackupURL(for settingsURL: URL) -> URL {
        settingsURL.deletingLastPathComponent().appendingPathComponent(".codex-quota-statusline-backup.json")
    }

    private static func settingsObject(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeBridgeError.invalidData
        }
        return object
    }

    private static func isOurStatusLine(_ value: Any?, command: String) -> Bool {
        guard let value = value as? [String: Any], value.count == 2 else { return false }
        return value["type"] as? String == "command" && value["command"] as? String == command
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
