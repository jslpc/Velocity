import SwiftUI

struct NewFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var remoteBrowser: RemoteBrowserViewModel
    
    @State private var folderName = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder Name", text: $folderName)
                        .focused($isTextFieldFocused)
                        .onSubmit {
                            createFolder()
                        }
                } header: {
                    Text("Create a new folder in:")
                } footer: {
                    Text(remoteBrowser.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createFolder()
                    }
                    .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 200)
        .onAppear {
            isTextFieldFocused = true
        }
    }
    
    private func createFolder() {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let connection = remoteBrowser.connection else { return }
        
        Task {
            do {
                let runner = try LFTPRunner()
                let openLine = buildOpenLine(connection)
                let currentPath = escape(remoteBrowser.path)
                let newFolderName = escape(trimmed)
                
                let command = "\(openLine); cd \(currentPath); mkdir \(newFolderName)"
                _ = try runner.runCommand(command)
                
                // Refresh the browser
                await remoteBrowser.refresh()
                dismiss()
            } catch {
                print("Create folder failed: \(error.localizedDescription)")
            }
        }
    }
    
    private func buildOpenLine(_ connection: LFTPConnection) -> String {
        let url = escape(connection.openURL)
        if connection.username.isEmpty {
            return "open \(url)"
        }
        let user = escape(connection.username)
        let pass = escape(connection.password)
        return "open -u \(user),\(pass) \(url)"
    }
    
    private func escape(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
