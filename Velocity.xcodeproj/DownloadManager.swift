import Foundation
import Combine

enum DownloadError: LocalizedError {
    case noConnection
    case invalidPath
    case downloadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No active connection to remote server"
        case .invalidPath:
            return "Invalid download path"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        }
    }
}

struct DownloadJob {
    let id = UUID()
    let remotePath: String
    let localPath: URL
    let displayName: String
    let isDirectory: Bool
    let connection: LFTPConnection
    let parallelDownloads: Int
    let segmentsPerFile: Int
}

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var currentJob: DownloadJob?
    @Published private(set) var statusText = "No active downloads"
    @Published private(set) var latestOutputLine: String?
    @Published private(set) var progress: Double = 0
    
    private var currentTask: Task<Void, Never>?
    private var pendingJobs: [DownloadJob] = []
    
    func enqueueDownload(
        remotePath: String,
        localPath: URL,
        displayName: String,
        isDirectory: Bool,
        connection: LFTPConnection,
        settings: TransferSettings
    ) {
        let job = DownloadJob(
            remotePath: remotePath,
            localPath: localPath,
            displayName: displayName,
            isDirectory: isDirectory,
            connection: connection,
            parallelDownloads: settings.parallelDownloads,
            segmentsPerFile: settings.segmentsPerFile
        )
        
        pendingJobs.append(job)
        statusText = "Queued: \(displayName)"
        
        if !isActive {
            processNextJob()
        }
    }
    
    func cancelAll() {
        currentTask?.cancel()
        currentTask = nil
        pendingJobs.removeAll()
        currentJob = nil
        isActive = false
        progress = 0
        statusText = "Downloads canceled"
    }
    
    private func processNextJob() {
        guard !pendingJobs.isEmpty else {
            isActive = false
            currentJob = nil
            statusText = "All downloads complete"
            return
        }
        
        let job = pendingJobs.removeFirst()
        currentJob = job
        isActive = true
        progress = 0
        statusText = "Downloading: \(job.displayName)"
        
        currentTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let runner = try LFTPRunner()
                let command = await self?.buildDownloadCommand(for: job) ?? ""
                
                _ = try runner.runCommand(command) { line in
                    Task { @MainActor [weak self] in
                        self?.handleOutput(line, for: job)
                    }
                }
                
                await MainActor.run { [weak self] in
                    self?.finishJob(job, success: true, message: "Downloaded: \(job.displayName)")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.finishJob(job, success: false, message: "Failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func buildDownloadCommand(for job: DownloadJob) -> String {
        let openLine = buildOpenLine(job.connection)
        let escapedRemote = escape(job.remotePath)
        let escapedLocal = escape(job.localPath.path)
        
        var commands = [
            "set net:timeout 30",
            "set net:max-retries 2",
            openLine,
        ]
        
        if job.isDirectory {
            // For directories, use mirror with parallel downloads
            // --preserve-time preserves modification timestamps
            let remoteDir = (job.remotePath as NSString).deletingLastPathComponent
            let remoteName = (job.remotePath as NSString).lastPathComponent
            
            commands.append("cd \(escape(remoteDir))")
            commands.append("lcd \(escapedLocal)")
            commands.append("mirror --verbose --preserve-time --parallel=\(job.parallelDownloads) --use-pget-n=\(job.segmentsPerFile) \(escape(remoteName))")
        } else {
            // For single files, use pget with segments
            // -c continues partial downloads, preserves timestamps
            let remoteDir = (job.remotePath as NSString).deletingLastPathComponent
            let remoteName = (job.remotePath as NSString).lastPathComponent
            
            commands.append("cd \(escape(remoteDir))")
            commands.append("lcd \(escapedLocal)")
            commands.append("pget -c -n \(job.segmentsPerFile) \(escape(remoteName))")
        }
        
        return commands.joined(separator: "; ")
    }
    
    private func buildOpenLine(_ connection: LFTPConnection) -> String {
        let url = escape(connection.openURL)
        if connection.username.isEmpty {
            return "open \(url)"
        }
        let user = escape(connection.username)
        let pass = escape(connection.password)
        return "open -u \(user),\(pass) \(url)"
    }
    
    private func escape(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
    
    private func handleOutput(_ line: String, for job: DownloadJob) {
        latestOutputLine = line
        
        // Try to extract progress from lftp output
        if let percent = extractPercent(line) {
            progress = min(max(percent / 100.0, 0), 1)
        }
        
        statusText = "Downloading: \(job.displayName)"
    }
    
    private func finishJob(_ job: DownloadJob, success: Bool, message: String) {
        currentTask = nil
        currentJob = nil
        latestOutputLine = message
        statusText = message
        
        // Process next job after a brief delay
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            processNextJob()
        }
    }
    
    private func extractPercent(_ line: String) -> Double? {
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
