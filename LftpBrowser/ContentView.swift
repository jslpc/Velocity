import SwiftUI

struct ContentView: View {
    @StateObject private var localBrowser = LocalBrowserViewModel()
    @StateObject private var remoteBrowser = RemoteBrowserViewModel()

    @State private var showConnectionSheet = false
    @State private var draftHost = ""
    @State private var draftUsername = ""
    @State private var draftPassword = ""
    @State private var draftUseSFTP = true

    /// Two primary columns (local + remote); detail is unused but required by `NavigationSplitView` on newer SDKs.
    @State private var splitVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var localSelection: String?
    @State private var remoteSelection: String?
    @State private var transferProgress: Double = 0
    @State private var isTransferActive = false
    @State private var transferStatus = "No active transfers"
    @State private var transferTask: Task<Void, Never>?

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
                        remoteSelection = nil
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
                .disabled(!canStartTransfer || isTransferActive)
                .help("Transfer the selected local item to the remote location")
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

    private var selectedLocalItem: FileItem? {
        guard let localSelection else { return nil }
        return localBrowser.items.first(where: { $0.id == localSelection })
    }

    private var selectedRemoteItem: FileItem? {
        guard let remoteSelection else { return nil }
        return remoteBrowser.items.first(where: { $0.id == remoteSelection })
    }

    private var canStartTransfer: Bool {
        selectedLocalItem != nil && remoteBrowser.connection != nil
    }

    private func refreshVisiblePanes() {
        Task { await localBrowser.refresh() }
        Task { await remoteBrowser.refresh() }
    }

    private func startTransfer() {
        guard canStartTransfer else { return }
        transferTask?.cancel()
        isTransferActive = true
        transferProgress = 0
        let localName = selectedLocalItem?.name ?? "selection"
        let destination = selectedRemoteItem?.name ?? remoteBrowser.path
        transferStatus = "Transferring \(localName) to \(destination)..."

        transferTask = Task { @MainActor in
            // Placeholder visual progress until transfer actions are wired to lftp get/put/mirror commands.
            while transferProgress < 1.0 {
                try? await Task.sleep(for: .milliseconds(120))
                if Task.isCancelled { return }
                transferProgress = min(transferProgress + 0.05, 1.0)
            }
            isTransferActive = false
            transferStatus = "Transfer complete"
        }
    }

    private var transferFooter: some View {
        VStack(spacing: 6) {
            if isTransferActive {
                ProgressView(value: transferProgress)
                    .progressViewStyle(.linear)
            }

            HStack(spacing: 8) {
                Image(systemName: isTransferActive ? "arrow.triangle.2.circlepath.circle.fill" : "externaldrive.badge.checkmark")
                    .foregroundStyle(isTransferActive ? Color.accentColor : Color.secondary)
                Text(transferStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if isTransferActive {
                    Text(transferProgress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
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
