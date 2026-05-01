import Foundation

struct FileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modificationDate: Date?

    var displayName: String {
        name
    }
}
