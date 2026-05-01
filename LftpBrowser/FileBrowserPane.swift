import SwiftUI

struct FileBrowserPane: View {
    let title: String
    let pathLabel: String
    let items: [FileItem]
    let isLoading: Bool
    let errorMessage: String?
    let onOpenItem: (FileItem) -> Void
    let onGoUp: () -> Void
    let onGoHome: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pathBar
            Divider()
            content
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: onGoUp) {
                    Label("Enclosing folder", systemImage: "arrow.up.square")
                }
                .help("Open parent folder")

                Button(action: onGoHome) {
                    Label("Home or root", systemImage: "house")
                }
                .help(title == "Local" ? "Go to your home folder" : "Go to server root")

                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh listing")
            }
        }
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
            List(items) { item in
                Button {
                    onOpenItem(item)
                } label: {
                    Label {
                        Text(item.displayName)
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(item.isDirectory ? .blue : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }
}
