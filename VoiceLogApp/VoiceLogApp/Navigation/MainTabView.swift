import SwiftUI

struct MainTabView: View {
    @ObservedObject var authService: AuthService

    var body: some View {
        TabView {
            NotesListView()
                .tabItem {
                    Label("Notes", systemImage: "doc.text")
                }

            SettingsView(authService: authService)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}

#Preview {
    MainTabView(authService: .shared)
}
