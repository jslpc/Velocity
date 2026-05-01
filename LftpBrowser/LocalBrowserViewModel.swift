import Foundation
import Combine

@MainActor
final class LocalBrowserViewModel: ObservableObject {
    @Published private(set) var path: URL
    @Published private(set) var items: [FileItem] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let fileManager = FileManager.default

    init(startURL: URL? = nil) {
        self.path = startURL ?? fileManager.homeDirectoryForCurrentUser
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
        path = path.appendingPathComponent(item.name, isDirectory: true)
        Task { await refresh() }
    }

    func goUp() {
        let parent = path.deletingLastPathComponent()
        if parent.path == path.path { return }
        path = parent
        Task { await refresh() }
    }

    func goHome() {
        path = fileManager.homeDirectoryForCurrentUser
        Task { await refresh() }
    }
}
