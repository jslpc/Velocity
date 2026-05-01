import Foundation

@MainActor
final class TransferSettings: ObservableObject {
    @Published var parallelDownloads: Int {
        didSet {
            UserDefaults.standard.set(parallelDownloads, forKey: "parallelDownloads")
        }
    }
    
    @Published var segmentsPerFile: Int {
        didSet {
            UserDefaults.standard.set(segmentsPerFile, forKey: "segmentsPerFile")
        }
    }
    
    init() {
        self.parallelDownloads = UserDefaults.standard.object(forKey: "parallelDownloads") as? Int ?? 5
        self.segmentsPerFile = UserDefaults.standard.object(forKey: "segmentsPerFile") as? Int ?? 5
        
        // Ensure values are in valid range
        if parallelDownloads < 1 || parallelDownloads > 20 {
            parallelDownloads = 5
        }
        if segmentsPerFile < 1 || segmentsPerFile > 20 {
            segmentsPerFile = 5
        }
    }
}
