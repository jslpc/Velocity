import Foundation
import Combine

@MainActor
final class RemoteBrowserViewModel: ObservableObject {
    @Published var connection: LFTPConnection?
    @Published private(set) var path: String = "/"
    @Published private(set) var items: [FileItem] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    func connect(_ connection: LFTPConnection) {
        self.connection = connection
        path = "/"
        Task { await refresh() }
    }

    func disconnect() {
        connection = nil
        path = "/"
        items = []
        errorMessage = nil
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
        path = item.id
        Task { await refresh() }
    }

    func goUp() {
        let nsPath = path as NSString
        var parent = nsPath.deletingLastPathComponent
        if parent.isEmpty { parent = "/" }
        path = parent
        Task { await refresh() }
    }

    func goRoot() {
        path = "/"
        Task { await refresh() }
    }
}
