import SwiftUI

struct SettingsView: View {
    @ObservedObject var authService: AuthService
    @StateObject private var syncState = SyncState.shared
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
                    // Show error banner if last sync failed
                    if case .failure(let error, _) = syncState.lastSyncResult {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Sync failed: \(error)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("sync_error_banner")
                    }

                    Button {
                        Task {
                            try? await SyncManager.shared.forceSync()
                        }
                    } label: {
                        HStack {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            if syncState.isSyncing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(syncState.isSyncing)
                    .accessibilityIdentifier("sync_now_button")

                    // Show last successful sync time
                    if case .success(let timestamp) = syncState.lastSyncResult {
                        HStack {
                            Text("Last synced")
                            Spacer()
                            Text(timestamp, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("settings_last_sync_time")
                    }
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
