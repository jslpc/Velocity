import Foundation

struct FavoriteServer: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var host: String
    var username: String
    var useSFTP: Bool
    var basePath: String
    
    // Password is NOT stored in favorites for security
    // Users will need to enter it when connecting
    
    func toConnection(password: String) -> LFTPConnection {
        LFTPConnection(
            host: host,
            username: username,
            password: password,
            useSFTP: useSFTP,
            basePath: basePath
        )
    }
}

@MainActor
final class FavoritesManager: ObservableObject {
    @Published var favorites: [FavoriteServer] = []
    
    private let favoritesKey = "savedFavoriteServers"
    
    init() {
        loadFavorites()
    }
    
    func addFavorite(_ favorite: FavoriteServer) {
        favorites.append(favorite)
        saveFavorites()
    }
    
    func removeFavorite(_ favorite: FavoriteServer) {
        favorites.removeAll { $0.id == favorite.id }
        saveFavorites()
    }
    
    func updateFavorite(_ favorite: FavoriteServer) {
        if let index = favorites.firstIndex(where: { $0.id == favorite.id }) {
            favorites[index] = favorite
            saveFavorites()
        }
    }
    
    private func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encoded, forKey: favoritesKey)
        }
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([FavoriteServer].self, from: data) {
            favorites = decoded
        }
    }
}
