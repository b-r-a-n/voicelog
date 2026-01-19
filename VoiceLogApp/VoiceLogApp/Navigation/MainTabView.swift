import SwiftUI

struct MainTabView: View {
    @ObservedObject var authService: AuthService

    var body: some View {
        TabView {
            NotesListView()
                .tabItem {
                    Label("Notes", systemImage: "doc.text")
                }
                .accessibilityIdentifier("notes_tab")

            SettingsView(authService: authService)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .accessibilityIdentifier("settings_tab")
        }
    }
}

#Preview {
    MainTabView(authService: .shared)
}
