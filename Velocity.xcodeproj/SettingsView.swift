import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: TransferSettings
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Parallel Downloads:")
                            .frame(width: 160, alignment: .leading)
                        Stepper("\(settings.parallelDownloads)", value: $settings.parallelDownloads, in: 1...20)
                            .frame(width: 120)
                    }
                    Text("Number of files to download simultaneously")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Segments Per File:")
                            .frame(width: 160, alignment: .leading)
                        Stepper("\(settings.segmentsPerFile)", value: $settings.segmentsPerFile, in: 1...20)
                            .frame(width: 120)
                    }
                    Text("Number of parallel connections for each file (pget -n)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Transfer Settings")
            } footer: {
                Text("These settings control how lftp downloads files. Higher values can improve speed but may increase server load.")
                    .font(.caption)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Single files use: pget -n \(settings.segmentsPerFile)")
                        .font(.caption.monospaced())
                    Text("• Folders use: mirror --parallel=\(settings.parallelDownloads) --use-pget-n=\(settings.segmentsPerFile)")
                        .font(.caption.monospaced())
                }
                .foregroundStyle(.secondary)
            } header: {
                Text("Commands Used")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(minWidth: 500, minHeight: 400)
    }
}
