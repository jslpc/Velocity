import SwiftUI
import AVKit
import UniformTypeIdentifiers
import AppKit

struct FilePreviewPane: View {
    let selectedItems: [FileItem]
    let isRemote: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Preview")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(.bar)
            
            ScrollView {
                if selectedItems.isEmpty {
                    emptyStateView
                } else if selectedItems.count == 1 {
                    singleFilePreview(selectedItems[0])
                } else {
                    multipleFilesPreview
                }
            }
        }
        .frame(minWidth: 250, idealWidth: 300)
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.image")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No Selection")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Select a file or folder to preview")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
    
    @ViewBuilder
    private func singleFilePreview(_ item: FileItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Thumbnail/Icon
            thumbnailView(for: item)
                .frame(maxWidth: .infinity)
                .padding()
            
            Divider()
            
            // File details
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Name", value: item.name)
                DetailRow(label: "Kind", value: fileKind(for: item))
                
                if let size = item.size {
                    DetailRow(label: "Size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                } else if item.isDirectory {
                    DetailRow(label: "Type", value: "Folder")
                }
                
                if let date = item.modificationDate {
                    DetailRow(label: "Modified", value: formatDate(date))
                }
                
                if !isRemote {
                    DetailRow(label: "Location", value: (item.id as NSString).deletingLastPathComponent)
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var multipleFilesPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Selected", value: "\(selectedItems.count) items")
                
                let folders = selectedItems.filter { $0.isDirectory }.count
                let files = selectedItems.count - folders
                
                if folders > 0 {
                    DetailRow(label: "Folders", value: "\(folders)")
                }
                if files > 0 {
                    DetailRow(label: "Files", value: "\(files)")
                }
                
                let totalSize = selectedItems.compactMap { $0.size }.reduce(0, +)
                if totalSize > 0 {
                    DetailRow(label: "Total Size", value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                }
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private func thumbnailView(for item: FileItem) -> some View {
        VStack {
            if item.isDirectory {
                Image(systemName: "folder.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
            } else if !isRemote, let thumbnail = generateThumbnail(for: item) {
                thumbnail
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .cornerRadius(8)
                    .shadow(radius: 2)
            } else {
                Image(systemName: iconName(for: item))
                    .font(.system(size: 64))
                    .foregroundStyle(iconColor(for: item))
            }
        }
    }
    
    private func generateThumbnail(for item: FileItem) -> Image? {
        let url = URL(fileURLWithPath: item.id)
        
        // Try QuickLook thumbnail
        if let cgImage = generateQuickLookThumbnail(for: url) {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return Image(nsImage: nsImage)
        }
        
        return nil
    }
    
    private func generateQuickLookThumbnail(for url: URL) -> CGImage? {
        let size = CGSize(width: 512, height: 512)
        let scale: CGFloat = 2.0
        
        // Use NSWorkspace icon for now - QuickLook requires async APIs
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        var rect = CGRect(origin: .zero, size: size)
        return icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
    
    private func iconName(for item: FileItem) -> String {
        if item.isDirectory {
            return "folder.fill"
        }
        
        let ext = (item.name as NSString).pathExtension.lowercased()
        
        switch ext {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic":
            return "photo"
        case "mp4", "mov", "avi", "mkv", "m4v":
            return "video.fill"
        case "mp3", "m4a", "wav", "aac", "flac":
            return "music.note"
        case "pdf":
            return "doc.fill"
        case "zip", "tar", "gz", "7z", "rar":
            return "doc.zipper"
        case "txt", "md", "rtf":
            return "doc.text"
        case "swift", "py", "js", "c", "cpp", "h", "m", "java":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc"
        }
    }
    
    private func iconColor(for item: FileItem) -> Color {
        if item.isDirectory {
            return .blue
        }
        
        let ext = (item.name as NSString).pathExtension.lowercased()
        
        switch ext {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic":
            return .orange
        case "mp4", "mov", "avi", "mkv", "m4v":
            return .purple
        case "mp3", "m4a", "wav", "aac", "flac":
            return .pink
        case "pdf":
            return .red
        case "zip", "tar", "gz", "7z", "rar":
            return .gray
        default:
            return .secondary
        }
    }
    
    private func fileKind(for item: FileItem) -> String {
        if item.isDirectory {
            return "Folder"
        }
        
        let ext = (item.name as NSString).pathExtension.lowercased()
        
        if ext.isEmpty {
            return "Document"
        }
        
        // Use UTType for better type detection
        if let utType = UTType(filenameExtension: ext) {
            return utType.localizedDescription ?? ext.uppercased() + " File"
        }
        
        return ext.uppercased() + " File"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    FilePreviewPane(
        selectedItems: [
            FileItem(
                id: "/Users/test/file.jpg",
                name: "file.jpg",
                isDirectory: false,
                size: 1024000,
                modificationDate: Date()
            )
        ],
        isRemote: false
    )
    .frame(width: 300, height: 600)
}
