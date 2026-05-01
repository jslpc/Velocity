import Foundation

struct FileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let isDirectory: Bool
    let size: Int64?

    var displayName: String {
        name
    }
}
