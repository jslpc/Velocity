import SwiftUI

struct ContentView: View {
    @StateObject private var localBrowser = LocalBrowserViewModel()
    @StateObject private var remoteBrowser = RemoteBrowserViewModel()
    @StateObject private var transferManager = LFTPTransferManager()

    @State private var showConnectionSheet = false
    @State private var draftHost = ""
    @State private var draftUsername = ""
    @State private var draftPassword = ""
    @State private var draftUseSFTP = true

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
                    onOpenItem: { localBrowser.open($0) }
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
                onConnect: { remoteBrowser.connect($0) }
            )
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
                onOpenItem: { remoteBrowser.open($0) }
            )
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

    private var transferFooter: some View {
        VStack(spacing: 6) {
            if transferManager.isActive {
                ProgressView(value: transferManager.overallProgress)
                    .progressViewStyle(.linear)
            }

            HStack(spacing: 8) {
                Image(systemName: transferManager.isActive ? "arrow.triangle.2.circlepath.circle.fill" : "externaldrive.badge.checkmark")
                    .foregroundStyle(transferManager.isActive ? Color.accentColor : Color.secondary)
                Text(transferManager.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if transferManager.isActive {
                    Text(transferManager.overallProgress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let line = transferManager.latestOutputLine {
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
