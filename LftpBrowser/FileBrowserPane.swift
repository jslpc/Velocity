import SwiftUI

struct FileBrowserPane: View {
    let title: String
    let pathLabel: String
    let items: [FileItem]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var selection: String?
    let onOpenItem: (FileItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pathBar
            Divider()
            content
        }
        .navigationTitle(title)
    }

    private var pathBar: some View {
        Text(pathLabel)
            .font(.system(.body, design: .monospaced))
            .lineLimit(2)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            ContentUnavailableView("Empty folder", systemImage: "folder", description: Text("This folder has no visible items."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(items, selection: $selection) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.isDirectory ? .blue : .secondary)
                    Text(item.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let size = item.size {
                        Text(size.formatted(.byteCount(style: .file)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let modified = item.modificationDate {
                        Text(modified, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .tag(item.id)
                .onTapGesture(count: 2) {
                    onOpenItem(item)
                }
            }
            .listStyle(.inset)
        }
    }
}
