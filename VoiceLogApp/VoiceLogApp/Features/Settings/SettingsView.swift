import SwiftUI

struct SettingsView: View {
    @ObservedObject var authService: AuthService
    @State private var showLogoutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let user = authService.currentUser {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading) {
                                Text(user.name)
                                    .font(.headline)
                                    .accessibilityIdentifier("settings_user_name")
                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("settings_user_email")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }

                Section("Sync") {
                    Button {
                        Task {
                            try? await SyncManager.shared.forceSync()
                        }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("sync_now_button")
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityIdentifier("signout_button")
                }
            }
            .accessibilityIdentifier("settings_screen")
            .navigationTitle("Settings")
            .confirmationDialog("Sign Out?", isPresented: $showLogoutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        await authService.logout()
                    }
                }
                .accessibilityIdentifier("signout_confirm_button")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out? Your notes will remain on the server.")
            }
        }
    }
}

#Preview {
    SettingsView(authService: .shared)
}
