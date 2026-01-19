import SwiftUI
import SwiftData

@main
struct VoiceLogApp: App {
    @StateObject private var authService = AuthService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .modelContainer(PersistenceController.shared.container)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showRegister = false

    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainTabView(authService: authService)
            } else {
                LoginView(showRegister: $showRegister)
                    .sheet(isPresented: $showRegister) {
                        RegisterView()
                    }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService.shared)
}
