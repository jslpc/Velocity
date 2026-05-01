import Foundation

enum LFTPError: LocalizedError {
    case lftpNotFound
    case commandFailed(String)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .lftpNotFound:
            return "The lftp executable was not found. Install it with Homebrew (brew install lftp) or ensure it is on your PATH."
        case .commandFailed(let message):
            return message
        case .parseFailed:
            return "Could not parse remote directory listing."
        }
    }
}

struct LFTPConnection: Equatable, Sendable {
    var host: String
    var username: String
    var password: String
    var useSFTP: Bool

    /// Host URL only; credentials are passed with `open -u` in the script.
    var openURL: String {
        let scheme = useSFTP ? "sftp" : "ftp"
        return "\(scheme)://\(host)"
    }
}

final class LFTPRunner {
    private let executableURL: URL

    init(executableURL: URL? = LFTPClient.resolvedExecutableURL()) throws {
        guard let executableURL else {
            throw LFTPError.lftpNotFound
        }
        self.executableURL = executableURL
    }

    /// Runs: lftp -c 'open [url]; cls --long'
    /// - Parameter url: FTP/SFTP URL accepted by lftp.
    /// - Returns: Combined stdout/stderr output for parser consumption.
    func listLong(url: String) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-c", "open \(escapeForLFTP(url)); cls --long"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmed.isEmpty ? "lftp exited with status \(process.terminationStatus)." : trimmed
            throw LFTPError.commandFailed(message)
        }

        return output
    }

    private func escapeForLFTP(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

enum LFTPListingParser {
    static func parseCLSLong(_ output: String, basePath: String = "/") -> [FileItem] {
        var items: [FileItem] = []
        let lines = output.split(whereSeparator: \.isNewline)

        for line in lines {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("total ") { continue }
            guard let parsed = parseLine(trimmed) else { continue }
            if parsed.name == "." || parsed.name == ".." { continue }

            let id = (basePath as NSString).appendingPathComponent(parsed.name)
            items.append(
                FileItem(
                    id: id,
                    name: parsed.name,
                    isDirectory: parsed.isDirectory,
                    size: parsed.size,
                    modificationDate: parsed.modificationDate
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func parseLine(_ line: String) -> (name: String, isDirectory: Bool, size: Int64?, modificationDate: Date?)? {
        guard let first = line.first else { return nil }
        let isDirectory = first == "d"
        let isFileLike = first == "-" || first == "l" || first == "b" || first == "c" || first == "p" || first == "s"
        guard isDirectory || isFileLike else { return nil }

        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 9 else { return nil }

        let size = Int64(String(parts[4]))
        let month = String(parts[5])
        let day = String(parts[6])
        let yearOrTime = String(parts[7])
        let rawName = parts.dropFirst(8).joined(separator: " ")
        guard !rawName.isEmpty else { return nil }

        // Symlink lines are typically "name -> target"; keep only link name.
        let name = rawName.components(separatedBy: " -> ").first ?? rawName
        let modificationDate = parseModificationDate(month: month, day: day, yearOrTime: yearOrTime)

        return (name, isDirectory, size, modificationDate)
    }

    private static func parseModificationDate(month: String, day: String, yearOrTime: String) -> Date? {
        let locale = Locale(identifier: "en_US_POSIX")
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)

        if yearOrTime.contains(":") {
            let currentYear = calendar.component(.year, from: now)
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "MMM d yyyy HH:mm"

            guard let date = formatter.date(from: "\(month) \(day) \(currentYear) \(yearOrTime)") else {
                return nil
            }

            // ls-style listings omit year for recent files. If date lands in the future, it's likely last year.
            if date > now.addingTimeInterval(24 * 60 * 60),
               let adjusted = calendar.date(byAdding: .year, value: -1, to: date) {
                return adjusted
            }
            return date
        } else {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "MMM d yyyy"
            return formatter.date(from: "\(month) \(day) \(yearOrTime)")
        }
    }
}

final class LFTPClient {
    private static let lftpPaths = [
        "/opt/homebrew/bin/lftp",
        "/usr/local/bin/lftp",
        "/usr/bin/lftp",
    ]

    static func resolvedExecutableURL() -> URL? {
        for path in lftpPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Runs a short non-interactive lftp script. Uses a temp file so quoting and multiline scripts are reliable.
    static func runScript(_ script: String) throws -> String {
        guard let lftpURL = resolvedExecutableURL() else {
            throw LFTPError.lftpNotFound
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("lftp-browser-\(UUID().uuidString).lftp")
        try script.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let process = Process()
        process.executableURL = lftpURL
        process.arguments = ["-f", fileURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmed.isEmpty ? "lftp exited with status \(process.terminationStatus)." : trimmed
            throw LFTPError.commandFailed(message)
        }

        return output
    }

    static func listRemote(connection: LFTPConnection, path: String) throws -> [FileItem] {
        let normalized = path.isEmpty ? "/" : path
        let escapedPath = escapeForLFTP(normalized)
        let openLine: String
        if connection.username.isEmpty {
            openLine = "open \(escapeForLFTP(connection.openURL));"
        } else {
            let u = escapeForLFTP(connection.username)
            let p = escapeForLFTP(connection.password)
            let url = escapeForLFTP(connection.openURL)
            openLine = "open -u \(u),\(p) \(url);"
        }

        let script = """
        set net:timeout 20;
        set net:max-retries 2;
        \(openLine)
        cd \(escapedPath);
        cls --long;
        """

        let output = try runScript(script)
        return LFTPListingParser.parseCLSLong(output, basePath: normalized)
    }

    private static func escapeForLFTP(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

}
