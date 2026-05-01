import SwiftUI
import AppKit

struct FileBrowserPane: View {
    let title: String
    let pathLabel: String
    let items: [FileItem]
    let isLoading: Bool
    let errorMessage: String?
    @Binding var selection: Set<String>
    let onOpenItem: (FileItem) -> Void
    
    // Navigation controls (optional - only for remote browser)
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var canGoUp: Bool = false
    var onGoBack: (() -> Void)? = nil
    var onGoForward: (() -> Void)? = nil
    var onGoUp: (() -> Void)? = nil
    var onGoToFolder: ((String) -> Void)? = nil
    
    // Remote-specific actions
    var isRemote: Bool = false
    var onDownload: ((FileItem, URL) -> Void)? = nil
    var onDownloadTo: ((FileItem) -> Void)? = nil
    var onDelete: ((FileItem) -> Void)? = nil
    var onNewFolder: (() -> Void)? = nil
    var onOpenWith: ((FileItem) -> Void)? = nil
    
    @State private var showGoToFolderSheet = false
    @State private var goToFolderPath = ""
    @State private var hoveredItemID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pathBar
            Divider()
            content
        }
        .navigationTitle(title)
        .sheet(isPresented: $showGoToFolderSheet) {
            GoToFolderSheet(
                currentPath: pathLabel,
                onGoToFolder: { path in
                    onGoToFolder?(path)
                    showGoToFolderSheet = false
                }
            )
        }
    }

    private var pathBar: some View {
        VStack(spacing: 0) {
            if onGoBack != nil || onGoForward != nil || onGoUp != nil {
                navigationToolbar
                Divider()
            }
            
            Text(pathLabel)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }
    
    @ViewBuilder
    private var navigationToolbar: some View {
        HStack(spacing: 8) {
            // Back button
            Button {
                onGoBack?()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!canGoBack)
            .help("Go Back")
            .keyboardShortcut("[", modifiers: .command)
            
            // Forward button
            Button {
                onGoForward?()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!canGoForward)
            .help("Go Forward")
            .keyboardShortcut("]", modifiers: .command)
            
            Divider()
                .frame(height: 20)
            
            // Up button
            Button {
                onGoUp?()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(!canGoUp)
            .help("Go to Parent Folder")
            .keyboardShortcut(.upArrow, modifiers: .command)
            
            Spacer()
            
            // Go to Folder button
            if onGoToFolder != nil {
                Button {
                    goToFolderPath = pathLabel
                    showGoToFolderSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Go to Folder…")
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
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
                FileRow(
                    item: item,
                    isHovered: hoveredItemID == item.id,
                    onHover: { isHovered in
                        hoveredItemID = isHovered ? item.id : nil
                    }
                )
                .contentShape(Rectangle())
                .tag(item.id)
                .onTapGesture(count: 2) {
                    onOpenItem(item)
                }
                .contextMenu {
                    fileContextMenu(for: item)
                }
            }
            .listStyle(.inset)
        }
    }
    
    @ViewBuilder
    private func fileContextMenu(for item: FileItem) -> some View {
        if isRemote {
            Button {
                // Download to Downloads folder
                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                onDownload?(item, downloadsURL)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            
            Button {
                onDownloadTo?(item)
            } label: {
                Label("Download to…", systemImage: "arrow.down.circle.dotted")
            }
            
            Divider()
        }
        
        Button {
            // Copy path to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(item.id, forType: .string)
        } label: {
            Label("Copy Path", systemImage: "doc.on.doc")
        }
        
        if isRemote {
            Divider()
            
            Button {
                onNewFolder?()
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            
            Divider()
            
            if !item.isDirectory {
                Button {
                    onOpenWith?(item)
                } label: {
                    Label("Open with…", systemImage: "arrow.up.forward.app")
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete?(item)
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
    }
}

// MARK: - File Row with Hover Effect

struct FileRow: View {
    let item: FileItem
    let isHovered: Bool
    let onHover: (Bool) -> Void
    
    var body: some View {
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
        .background(isHovered ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.3) : Color.clear)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                onHover(true)
            case .ended:
                onHover(false)
            }
        }
    }
}

// MARK: - Go to Folder Sheet

struct GoToFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let currentPath: String
    let onGoToFolder: (String) -> Void
    
    @State private var folderPath: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder Path", text: $folderPath, prompt: Text(currentPath))
                        .font(.system(.body, design: .monospaced))
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            goToFolder()
                        }
                } header: {
                    Text("Enter the path to the folder you want to navigate to:")
                }
                
                Section {
                    Text("Examples:")
                        .font(.caption.weight(.semibold))
                    Text("/home/username/Documents")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("/var/www/html")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("../sibling-folder")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color(nsColor: .controlBackgroundColor))
            }
            .formStyle(.grouped)
            .navigationTitle("Go to Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Go") {
                        goToFolder()
                    }
                    .disabled(folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 450, minHeight: 280)
        .onAppear {
            folderPath = currentPath
            isTextFieldFocused = true
        }
    }
    
    private func goToFolder() {
        let trimmed = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onGoToFolder(trimmed)
        dismiss()
    }
}
