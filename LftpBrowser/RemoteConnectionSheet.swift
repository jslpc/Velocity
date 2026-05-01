import SwiftUI

struct RemoteConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var host: String
    @Binding var username: String
    @Binding var password: String
    @Binding var useSFTP: Bool

    var onConnect: (LFTPConnection) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Host", text: $host)
                        .textContentType(.URL)
                    Toggle("Use SFTP (SSH)", isOn: $useSFTP)
                }
                Section("Credentials") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                Section {
                    Text("Requires lftp on this Mac (for example `brew install lftp`). Password is sent to the lftp process for this session only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Connect to Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        let connection = LFTPConnection(
                            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                            password: password,
                            useSFTP: useSFTP
                        )
                        onConnect(connection)
                        dismiss()
                    }
                    .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 320)
    }
}
