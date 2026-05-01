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

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            NavigationStack {
                FileBrowserPane(
                    title: "Local",
                    pathLabel: localBrowser.path.path,
                    items: localBrowser.items,
                    isLoading: localBrowser.isLoading,
                    errorMessage: localBrowser.errorMessage,
                    onOpenItem: { localBrowser.open($0) },
                    onGoUp: { localBrowser.goUp() },
                    onGoHome: { localBrowser.goHome() },
                    onRefresh: { Task { await localBrowser.refresh() } }
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
                onOpenItem: { remoteBrowser.open($0) },
                onGoUp: { remoteBrowser.goUp() },
                onGoHome: { remoteBrowser.goRoot() },
                onRefresh: { Task { await remoteBrowser.refresh() } }
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Disconnect", role: .destructive) {
                        remoteBrowser.disconnect()
                    }
                }
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
}

#Preview {
    ContentView()
}
