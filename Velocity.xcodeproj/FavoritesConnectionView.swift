import SwiftUI

struct FavoritesConnectionView: View {
    @ObservedObject var favoritesManager: FavoritesManager
    @Binding var isPresented: Bool
    let onConnect: (LFTPConnection) -> Void
    
    @State private var selectedFavorite: FavoriteServer?
    @State private var showingAddFavorite = false
    @State private var showingEditFavorite = false
    
    // New/Quick connection fields
    @State private var quickHost = ""
    @State private var quickUsername = ""
    @State private var quickPassword = ""
    @State private var quickUseSFTP = true
    @State private var quickBasePath = ""
    
    // Password for selected favorite
    @State private var favoritePassword = ""
    
    var body: some View {
        NavigationStack {
            HSplitView {
                // Left: Favorites list
                VStack(alignment: .leading, spacing: 0) {
                    Text("Favorites")
                        .font(.headline)
                        .padding()
                    
                    if favoritesManager.favorites.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "star.slash")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("No favorites yet")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(selection: $selectedFavorite) {
                            ForEach(favoritesManager.favorites) { favorite in
                                FavoriteRow(favorite: favorite)
                                    .tag(favorite)
                                    .contextMenu {
                                        Button {
                                            selectedFavorite = favorite
                                            showingEditFavorite = true
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        
                                        Button(role: .destructive) {
                                            favoritesManager.removeFavorite(favorite)
                                            if selectedFavorite?.id == favorite.id {
                                                selectedFavorite = nil
                                                favoritePassword = ""
                                            }
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                    
                    Button {
                        showingAddFavorite = true
                    } label: {
                        Label("Add Favorite", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .padding()
                }
                .frame(minWidth: 250, idealWidth: 300)
                
                Divider()
                
                // Right: Connection details
                VStack(alignment: .leading, spacing: 0) {
                    if let favorite = selectedFavorite {
                        // Connect to favorite
                        favoriteConnectionView(favorite)
                    } else {
                        // Quick connection
                        quickConnectionView
                    }
                }
                .frame(minWidth: 350)
            }
            .navigationTitle("Connect to Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .frame(minWidth: 700, minHeight: 500)
        }
        .sheet(isPresented: $showingAddFavorite) {
            EditFavoriteSheet(
                favorite: nil,
                onSave: { newFavorite in
                    favoritesManager.addFavorite(newFavorite)
                    showingAddFavorite = false
                },
                onCancel: {
                    showingAddFavorite = false
                }
            )
        }
        .sheet(isPresented: $showingEditFavorite) {
            if let favorite = selectedFavorite {
                EditFavoriteSheet(
                    favorite: favorite,
                    onSave: { updatedFavorite in
                        favoritesManager.updateFavorite(updatedFavorite)
                        selectedFavorite = updatedFavorite
                        showingEditFavorite = false
                    },
                    onCancel: {
                        showingEditFavorite = false
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private func favoriteConnectionView(_ favorite: FavoriteServer) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect to \(favorite.name)")
                .font(.title2.bold())
                .padding(.horizontal)
                .padding(.top)
            
            Form {
                Section {
                    LabeledContent("Server:", value: favorite.host)
                    LabeledContent("Username:", value: favorite.username)
                    LabeledContent("Protocol:", value: favorite.useSFTP ? "SFTP" : "FTP")
                    if !favorite.basePath.isEmpty {
                        LabeledContent("Path:", value: favorite.basePath)
                    }
                }
                
                Section {
                    SecureField("Password", text: $favoritePassword)
                        .onSubmit {
                            connectToFavorite(favorite)
                        }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text("Passwords are not saved for security reasons.")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Spacer()
                Button("Connect") {
                    connectToFavorite(favorite)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(favoritePassword.isEmpty)
                .padding()
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var quickConnectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Connect")
                .font(.title2.bold())
                .padding(.horizontal)
                .padding(.top)
            
            Form {
                Section {
                    TextField("Server", text: $quickHost)
                        .textContentType(.URL)
                    TextField("Username", text: $quickUsername)
                        .textContentType(.username)
                    SecureField("Password", text: $quickPassword)
                        .textContentType(.password)
                    Toggle("Use SFTP", isOn: $quickUseSFTP)
                    TextField("Base Path (optional)", text: $quickBasePath)
                        .textContentType(.none)
                } header: {
                    Text("Server Details")
                } footer: {
                    Text("Enter server connection details for a one-time connection.")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button {
                    saveAsNewFavorite()
                } label: {
                    Label("Save as Favorite", systemImage: "star")
                }
                .disabled(quickHost.isEmpty || quickUsername.isEmpty)
                
                Spacer()
                
                Button("Connect") {
                    connectQuick()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canConnectQuick)
            }
            .padding()
            
            Spacer()
        }
    }
    
    private var canConnectQuick: Bool {
        !quickHost.isEmpty && !quickUsername.isEmpty && !quickPassword.isEmpty
    }
    
    private func connectToFavorite(_ favorite: FavoriteServer) {
        let connection = favorite.toConnection(password: favoritePassword)
        onConnect(connection)
        isPresented = false
    }
    
    private func connectQuick() {
        let connection = LFTPConnection(
            host: quickHost,
            username: quickUsername,
            password: quickPassword,
            useSFTP: quickUseSFTP,
            basePath: quickBasePath
        )
        onConnect(connection)
        isPresented = false
    }
    
    private func saveAsNewFavorite() {
        let favorite = FavoriteServer(
            name: quickHost, // Default name to host
            host: quickHost,
            username: quickUsername,
            useSFTP: quickUseSFTP,
            basePath: quickBasePath
        )
        favoritesManager.addFavorite(favorite)
        selectedFavorite = favorite
        favoritePassword = quickPassword
        
        // Clear quick connection fields
        quickHost = ""
        quickUsername = ""
        quickPassword = ""
        quickUseSFTP = true
        quickBasePath = ""
    }
}

struct FavoriteRow: View {
    let favorite: FavoriteServer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .imageScale(.small)
                Text(favorite.name)
                    .font(.headline)
            }
            Text("\(favorite.username)@\(favorite.host)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(favorite.useSFTP ? "SFTP" : "FTP")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(favorite.useSFTP ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}

struct EditFavoriteSheet: View {
    let favorite: FavoriteServer?
    let onSave: (FavoriteServer) -> Void
    let onCancel: () -> Void
    
    @State private var name: String
    @State private var host: String
    @State private var username: String
    @State private var useSFTP: Bool
    @State private var basePath: String
    
    init(favorite: FavoriteServer?, onSave: @escaping (FavoriteServer) -> Void, onCancel: @escaping () -> Void) {
        self.favorite = favorite
        self.onSave = onSave
        self.onCancel = onCancel
        
        _name = State(initialValue: favorite?.name ?? "")
        _host = State(initialValue: favorite?.host ?? "")
        _username = State(initialValue: favorite?.username ?? "")
        _useSFTP = State(initialValue: favorite?.useSFTP ?? true)
        _basePath = State(initialValue: favorite?.basePath ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Server", text: $host)
                    TextField("Username", text: $username)
                    Toggle("Use SFTP", isOn: $useSFTP)
                    TextField("Base Path (optional)", text: $basePath)
                } header: {
                    Text("Server Details")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(favorite == nil ? "Add Favorite" : "Edit Favorite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .frame(minWidth: 400, minHeight: 300)
        }
    }
    
    private var canSave: Bool {
        !name.isEmpty && !host.isEmpty && !username.isEmpty
    }
    
    private func save() {
        let newFavorite = FavoriteServer(
            id: favorite?.id ?? UUID(),
            name: name,
            host: host,
            username: username,
            useSFTP: useSFTP,
            basePath: basePath
        )
        onSave(newFavorite)
    }
}
