import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var localBrowser = LocalBrowserViewModel()
    @StateObject private var remoteBrowser = RemoteBrowserViewModel()
    @StateObject private var transferManager = LFTPTransferManager()
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var transferSettings = TransferSettings()

    @State private var showConnectionSheet = false
    @State private var showSettingsSheet = false
    @State private var showNewFolderSheet = false
    @State private var showDeleteConfirmation = false
    @State private var itemToDelete: FileItem?
    @State private var draftHost = ""
    @State private var draftUsername = ""
    @State private var draftPassword = ""
    @State private var draftUseSFTP = true
    @State private var draftBasePath = ""

    /// Two primary columns (local + remote); detail is unused but required by `NavigationSplitView` on newer SDKs.
    @State private var splitVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var localSelection: Set<String> = []
    @State private var remoteSelection: Set<String> = []

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            NavigationStack {
                FileBrowserPane(
                    title: "Local",
                    pathLabel: localBrowser.path.path,
                    items: localBrowser.items,
                    isLoading: localBrowser.isLoading,
                    errorMessage: localBrowser.errorMessage,
                    selection: $localSelection,
                    onOpenItem: { localBrowser.open($0) },
                    canGoBack: localBrowser.canGoBack,
                    canGoForward: localBrowser.canGoForward,
                    canGoUp: localBrowser.canGoUp,
                    onGoBack: { localBrowser.goBack() },
                    onGoForward: { localBrowser.goForward() },
                    onGoUp: { localBrowser.goUp() },
                    onGoToFolder: { localBrowser.goToFolder($0) }
                )
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 520, max: .infinity)
        } content: {
            NavigationStack {
                remotePane
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 520, max: .infinity)
        } detail: {
            EmptyView()
        }
        .sheet(isPresented: $showConnectionSheet) {
            RemoteConnectionSheet(
                host: $draftHost,
                username: $draftUsername,
                password: $draftPassword,
                useSFTP: $draftUseSFTP,
                basePath: $draftBasePath,
                onConnect: { remoteBrowser.connect($0) }
            )
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView(settings: transferSettings)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "wrench")
                }
                .help("Transfer Settings")
                
                Button {
                    if remoteBrowser.connection == nil {
                        showConnectionSheet = true
                    } else {
                        remoteBrowser.disconnect()
                        remoteSelection = []
                    }
                } label: {
                    Label(remoteBrowser.connection == nil ? "Connect" : "Disconnect", systemImage: "link")
                }
                .help(remoteBrowser.connection == nil ? "Connect to a remote server" : "Disconnect from remote server")

                Button {
                    refreshVisiblePanes()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh local and remote listings")

                Button {
                    startTransfer()
                } label: {
                    Label("Transfer", systemImage: "arrow.left.arrow.right.circle")
                }
                .disabled(!canStartTransfer)
                .help("Queue selected local items for transfer to the remote location")
            }
        }
        .safeAreaInset(edge: .bottom) {
            transferFooter
        }
    }

    @ViewBuilder
    private var remotePane: some View {
        if remoteBrowser.connection != nil {
            FileBrowserPane(
                title: "Remote",
                pathLabel: remoteBrowser.path,
                items: remoteBrowser.items,
                isLoading: remoteBrowser.isLoading,
                errorMessage: remoteBrowser.errorMessage,
                selection: $remoteSelection,
                onOpenItem: { remoteBrowser.open($0) },
                canGoBack: remoteBrowser.canGoBack,
                canGoForward: remoteBrowser.canGoForward,
                canGoUp: remoteBrowser.canGoUp,
                onGoBack: { remoteBrowser.goBack() },
                onGoForward: { remoteBrowser.goForward() },
                onGoUp: { remoteBrowser.goUp() },
                onGoToFolder: { remoteBrowser.goToFolder($0) },
                isRemote: true,
                onDownload: { item, destination in
                    downloadFile(item, to: destination)
                },
                onDownloadTo: { item in
                    downloadFileTo(item)
                },
                onDelete: { item in
                    itemToDelete = item
                    showDeleteConfirmation = true
                },
                onNewFolder: {
                    showNewFolderSheet = true
                },
                onOpenWith: { item in
                    openFileWith(item)
                }
            )
            .confirmationDialog(
                "Move to Trash",
                isPresented: $showDeleteConfirmation,
                presenting: itemToDelete
            ) { item in
                Button("Move to Trash", role: .destructive) {
                    deleteRemoteItem(item)
                }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text("Are you sure you want to delete \"\(item.name)\" from the remote server? This action cannot be undone.")
            }
            .sheet(isPresented: $showNewFolderSheet) {
                NewFolderSheet(remoteBrowser: remoteBrowser)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "server.rack")
                    .font(.system(size: 48))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text("Remote")
                    .font(.title2.weight(.semibold))
                Text("Connect to an FTP or SFTP server to browse files with lftp.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320)
                Button {
                    showConnectionSheet = true
                } label: {
                    Label("Connect to Server…", systemImage: "link")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Remote")
        }
    }

    private var selectedLocalItems: [FileItem] {
        localBrowser.items.filter { localSelection.contains($0.id) }
    }

    private var selectedRemoteItem: FileItem? {
        guard let selectedID = remoteSelection.first else { return nil }
        return remoteBrowser.items.first(where: { $0.id == selectedID })
    }

    private var canStartTransfer: Bool {
        !selectedLocalItems.isEmpty && remoteBrowser.connection != nil
    }

    private func refreshVisiblePanes() {
        Task { await localBrowser.refresh() }
        Task { await remoteBrowser.refresh() }
    }

    private func startTransfer() {
        guard let connection = remoteBrowser.connection else { return }
        let remoteBasePath: String
        if let selectedRemoteItem, selectedRemoteItem.isDirectory {
            remoteBasePath = selectedRemoteItem.id
        } else {
            remoteBasePath = remoteBrowser.path
        }

        let urls = selectedLocalItems.map { URL(fileURLWithPath: $0.id) }
        transferManager.enqueueUploads(localURLs: urls, connection: connection, remoteDirectory: remoteBasePath)
    }
    
    private func downloadFile(_ item: FileItem, to destination: URL) {
        guard let connection = remoteBrowser.connection else { return }
        
        downloadManager.enqueueDownload(
            remotePath: item.id,
            localPath: destination,
            displayName: item.name,
            isDirectory: item.isDirectory,
            connection: connection,
            settings: transferSettings
        )
    }
    
    private func downloadFileTo(_ item: FileItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose download destination for \(item.name)"
        panel.prompt = "Download"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            downloadFile(item, to: url)
        }
    }
    
    private func deleteRemoteItem(_ item: FileItem) {
        guard let connection = remoteBrowser.connection else { return }
        
        Task {
            do {
                let runner = try LFTPRunner()
                let openLine = buildOpenLine(connection)
                let remotePath = escape(item.id)
                let command: String
                
                if item.isDirectory {
                    command = "\(openLine); rm -r \(remotePath)"
                } else {
                    command = "\(openLine); rm \(remotePath)"
                }
                
                _ = try runner.runCommand(command)
                
                // Refresh the remote browser
                await remoteBrowser.refresh()
            } catch {
                // Show error to user
                print("Delete failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func openFileWith(_ item: FileItem) {
        guard let connection = remoteBrowser.connection else { return }
        
        // Download to temp directory first
        let tempDir = FileManager.default.temporaryDirectory
        let tempDestination = tempDir.appendingPathComponent(UUID().uuidString)
        
        downloadManager.enqueueDownload(
            remotePath: item.id,
            localPath: tempDestination,
            displayName: item.name,
            isDirectory: false,
            connection: connection,
            settings: transferSettings
        )
        
        // TODO: Watch for download completion and open file
        // For now, just download it - user can open from Downloads folder
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let fileURL = tempDestination.appendingPathComponent(item.name)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                NSWorkspace.shared.open(fileURL)
            }
        }
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

    private var transferFooter: some View {
        VStack(spacing: 6) {
            if transferManager.isActive || downloadManager.isActive {
                ProgressView(value: transferManager.isActive ? transferManager.overallProgress : downloadManager.progress)
                    .progressViewStyle(.linear)
            }

            HStack(spacing: 8) {
                Image(systemName: (transferManager.isActive || downloadManager.isActive) ? "arrow.triangle.2.circlepath.circle.fill" : "externaldrive.badge.checkmark")
                    .foregroundStyle((transferManager.isActive || downloadManager.isActive) ? Color.accentColor : Color.secondary)
                Text(downloadManager.isActive ? downloadManager.statusText : transferManager.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if transferManager.isActive {
                    Text(transferManager.overallProgress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if downloadManager.isActive {
                    Text(downloadManager.progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let line = (downloadManager.isActive ? downloadManager.latestOutputLine : transferManager.latestOutputLine) {
                Text(line)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

#Preview {
    ContentView()
}
