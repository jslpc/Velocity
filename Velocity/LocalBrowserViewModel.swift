import Foundation
import Combine

@MainActor
final class LocalBrowserViewModel: ObservableObject {
    @Published private(set) var path: URL
    @Published private(set) var items: [FileItem] = []
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published private(set) var pathHistory: [URL] = []
    @Published private(set) var historyIndex: Int = 0

    private let fileManager = FileManager.default

    var canGoBack: Bool {
        historyIndex > 0
    }

    var canGoForward: Bool {
        historyIndex < pathHistory.count - 1
    }

    var canGoUp: Bool {
        let parent = path.deletingLastPathComponent()
        return parent.path != path.path
    }

    init(startURL: URL? = nil) {
        let initialPath = startURL ?? fileManager.homeDirectoryForCurrentUser
        self.path = initialPath
        self.pathHistory = [initialPath]
        self.historyIndex = 0
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let urls = try fileManager.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            var built: [FileItem] = []
            for url in urls {
                let name = url.lastPathComponent
                if name == "." || name == ".." { continue }
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                let isDir = values.isDirectory ?? false
                let size = isDir ? nil : Int64(values.fileSize ?? 0)
                built.append(
                    FileItem(
                        id: url.path,
                        name: name,
                        isDirectory: isDir,
                        size: size,
                        modificationDate: values.contentModificationDate
                    )
                )
            }

            items = built.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory && !rhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
    }

    func open(_ item: FileItem) {
        guard item.isDirectory else { return }
        navigateTo(path.appendingPathComponent(item.name, isDirectory: true))
    }

    func goUp() {
        let parent = path.deletingLastPathComponent()
        if parent.path == path.path { return }
        navigateTo(parent)
    }

    func goHome() {
        navigateTo(fileManager.homeDirectoryForCurrentUser)
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
        
        let folderURL = URL(fileURLWithPath: trimmed, isDirectory: true)
        navigateTo(folderURL)
    }

    private func navigateTo(_ newPath: URL) {
        guard newPath.path != path.path else { return }
        
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
