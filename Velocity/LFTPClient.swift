import Foundation
import Combine

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
        try runCommand("open \(escapeForLFTP(url)); cls --long")
    }

    func runCommand(_ command: String, onLine: (@Sendable (String) -> Void)? = nil) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-c", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collector = StreamCollector(onLine: onLine)

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            collector.append(chunk)
        }

        try process.run()
        process.waitUntilExit()
        pipe.fileHandleForReading.readabilityHandler = nil

        let trailing = pipe.fileHandleForReading.readDataToEndOfFile()
        if !trailing.isEmpty, let trailingChunk = String(data: trailing, encoding: .utf8) {
            collector.append(trailingChunk)
        }

        collector.finish()

        let output = collector.output

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

private final class StreamCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var output = ""
    private var partialLine = ""
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    func append(_ chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        output.append(chunk)
        guard let onLine else { return }

        partialLine.append(chunk)
        let parts = partialLine.components(separatedBy: .newlines)
        for line in parts.dropLast() where !line.isEmpty {
            onLine(line)
        }
        partialLine = parts.last ?? ""
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard let onLine else { return }
        let finalLine = partialLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalLine.isEmpty {
            onLine(finalLine)
        }
    }
}

private struct LFTPTransferJob {
    let id = UUID()
    let displayName: String
    let command: String
}

@MainActor
final class LFTPTransferManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var overallProgress: Double = 0
    @Published private(set) var statusText = "No active transfers"
    @Published private(set) var latestOutputLine: String?
    @Published private(set) var queuedCount = 0
    @Published private(set) var runningCount = 0

    private let maxParallelTransfers = 2
    private var pendingJobs: [LFTPTransferJob] = []
    private var runningProgress: [UUID: Double] = [:]
    private var totalJobs = 0
    private var completedJobs = 0
    private var failedJobs = 0
    private var workerTasks: [UUID: Task<Void, Never>] = [:]

    func enqueueUploads(localURLs: [URL], connection: LFTPConnection, remoteDirectory: String) {
        let jobs = localURLs.map { localURL in
            LFTPTransferJob(
                displayName: localURL.lastPathComponent,
                command: Self.uploadCommand(for: localURL, connection: connection, remoteDirectory: remoteDirectory)
            )
        }

        guard !jobs.isEmpty else { return }
        pendingJobs.append(contentsOf: jobs)
        totalJobs += jobs.count
        queuedCount = pendingJobs.count
        statusText = "Queued \(pendingJobs.count) transfer(s)"
        isActive = true
        launchNextJobsIfPossible()
    }

    func cancelAll() {
        for task in workerTasks.values {
            task.cancel()
        }
        workerTasks.removeAll()
        pendingJobs.removeAll()
        runningProgress.removeAll()
        queuedCount = 0
        runningCount = 0
        isActive = false
        statusText = "Transfers canceled"
        overallProgress = 0
    }

    private func launchNextJobsIfPossible() {
        while runningProgress.count < maxParallelTransfers, !pendingJobs.isEmpty {
            let job = pendingJobs.removeFirst()
            queuedCount = pendingJobs.count
            runningProgress[job.id] = 0
            runningCount = runningProgress.count
            updateOverallProgress()

            let task = Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                do {
                    let runner = try LFTPRunner()
                    _ = try runner.runCommand(job.command) { line in
                        Task { @MainActor [weak self] in
                            self?.handleOutput(line, for: job.id)
                        }
                    }
                    await MainActor.run {
                        self.finish(jobID: job.id, didFail: false, message: "Transferred \(job.displayName)")
                    }
                } catch {
                    await MainActor.run {
                        self.finish(jobID: job.id, didFail: true, message: "Failed \(job.displayName): \(error.localizedDescription)")
                    }
                }
            }
            workerTasks[job.id] = task
        }
    }

    private func handleOutput(_ line: String, for jobID: UUID) {
        latestOutputLine = line
        if let percent = Self.extractPercent(line) {
            runningProgress[jobID] = min(max(percent / 100.0, 0), 1)
            updateOverallProgress()
        }
        statusText = "Running \(runningProgress.count), queued \(pendingJobs.count)"
    }

    private func finish(jobID: UUID, didFail: Bool, message: String) {
        workerTasks[jobID] = nil
        runningProgress[jobID] = nil
        runningCount = runningProgress.count
        if didFail {
            failedJobs += 1
        } else {
            completedJobs += 1
        }
        latestOutputLine = message
        launchNextJobsIfPossible()
        updateOverallProgress()

        if runningProgress.isEmpty, pendingJobs.isEmpty {
            isActive = false
            let totalDone = completedJobs + failedJobs
            statusText = "Completed \(completedJobs)/\(totalDone) transfers"
        }
    }

    private func updateOverallProgress() {
        guard totalJobs > 0 else {
            overallProgress = 0
            return
        }

        let runningFraction = runningProgress.values.reduce(0, +)
        let done = Double(completedJobs) + runningFraction
        overallProgress = min(max(done / Double(totalJobs), 0), 1)
    }

    private static func uploadCommand(for localURL: URL, connection: LFTPConnection, remoteDirectory: String) -> String {
        let remoteDir = remoteDirectory.isEmpty ? "/" : remoteDirectory
        let name = localURL.lastPathComponent
        let openLine = openCommandLine(connection)
        let escapedParent = escape(localURL.deletingLastPathComponent().path)
        let escapedName = escape(name)
        let escapedRemoteDir = escape(remoteDir)

        var commands = [
            "set net:timeout 30",
            "set net:max-retries 2",
            openLine,
            "lcd \(escapedParent)",
            "mkdir -p \(escapedRemoteDir)",
        ]

        let isDir = (try? localURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDir {
            commands.append("mirror -R \(escapedName) \(escapedRemoteDir)/\(escapedName)")
        } else {
            commands.append("cd \(escapedRemoteDir)")
            commands.append("put \(escapedName)")
        }

        return commands.joined(separator: "; ")
    }

    private static func openCommandLine(_ connection: LFTPConnection) -> String {
        let url = escape(connection.openURL)
        if connection.username.isEmpty {
            return "open \(url)"
        }
        let user = escape(connection.username)
        let pass = escape(connection.password)
        return "open -u \(user),\(pass) \(url)"
    }

    private static func escape(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func extractPercent(_ line: String) -> Double? {
        let pattern = #"([0-9]{1,3})%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.matches(in: line, range: range).last,
              let valueRange = Range(match.range(at: 1), in: line),
              let value = Double(line[valueRange]) else {
            return nil
        }
        return min(max(value, 0), 100)
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
