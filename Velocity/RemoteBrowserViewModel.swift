import Foundation
import Combine

@MainActor
final class RemoteBrowserViewModel: ObservableObject {
    @Published var connection: LFTPConnection?
    @Published private(set) var path: String = "/"
    @Published private(set) var items: [FileItem] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published private(set) var pathHistory: [String] = ["/"]
    @Published private(set) var historyIndex: Int = 0

    var canGoBack: Bool {
        historyIndex > 0
    }

    var canGoForward: Bool {
        historyIndex < pathHistory.count - 1
    }

    var canGoUp: Bool {
        path != "/"
    }

    func connect(_ connection: LFTPConnection) {
        self.connection = connection
        let startPath = connection.normalizedBasePath
        path = startPath
        pathHistory = [startPath]
        historyIndex = 0
        Task { await refresh() }
    }

    func disconnect() {
        connection = nil
        path = "/"
        items = []
        errorMessage = nil
        pathHistory = ["/"]
        historyIndex = 0
    }

    func refresh() async {
        guard let connection else {
            items = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let currentPath = path
        do {
            items = try await Task.detached(priority: .userInitiated) {
                try LFTPClient.listRemote(connection: connection, path: currentPath)
            }.value
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
    }

    func open(_ item: FileItem) {
        guard item.isDirectory else { return }
        navigateTo(item.id)
    }

    func goUp() {
        let nsPath = path as NSString
        var parent = nsPath.deletingLastPathComponent
        if parent.isEmpty { parent = "/" }
        navigateTo(parent)
    }

    func goRoot() {
        navigateTo("/")
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        path = pathHistory[historyIndex]
        Task { await refresh() }
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        path = pathHistory[historyIndex]
        Task { await refresh() }
    }

    func goToFolder(_ folderPath: String) {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        navigateTo(trimmed)
    }

    private func navigateTo(_ newPath: String) {
        guard newPath != path else { return }
        
        // Remove any forward history when navigating to a new path
        if historyIndex < pathHistory.count - 1 {
            pathHistory.removeSubrange((historyIndex + 1)...)
        }
        
        path = newPath
        pathHistory.append(newPath)
        historyIndex = pathHistory.count - 1
        
        Task { await refresh() }
    }
}
