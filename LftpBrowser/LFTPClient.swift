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
        ls -la;
        """

        let output = try runScript(script)
        return parseLSLA(output, basePath: normalized)
    }

    private static func escapeForLFTP(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func parseLSLA(_ output: String, basePath: String) -> [FileItem] {
        var items: [FileItem] = []
        let lines = output.split(whereSeparator: \.isNewline)

        for line in lines {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("total ") { continue }
            if trimmed == "." || trimmed == ".." { continue }

            guard let parsed = parseLSLine(trimmed) else { continue }
            if parsed.name == "." || parsed.name == ".." { continue }

            let id = (basePath as NSString).appendingPathComponent(parsed.name)
            items.append(FileItem(id: id, name: parsed.name, isDirectory: parsed.isDirectory, size: parsed.size))
        }

        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func parseLSLine(_ line: String) -> (name: String, isDirectory: Bool, size: Int64?)? {
        guard let first = line.first else { return nil }
        let isDirectory = first == "d"
        let isFileLike = first == "-" || first == "l" || first == "b" || first == "c" || first == "p" || first == "s"
        guard isDirectory || isFileLike else { return nil }

        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 9 else { return nil }

        let sizeString = String(parts[4])
        let size = Int64(sizeString)

        let nameParts = parts.dropFirst(8)
        let name = nameParts.joined(separator: " ")
        guard !name.isEmpty else { return nil }

        return (name, isDirectory, size)
    }
}
