import SwiftUI

struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $viewModel.name)
                        .textContentType(.name)
                        .accessibilityIdentifier("register_name_field")

                    TextField("Email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .accessibilityIdentifier("register_email_field")

                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("register_password_field")

                    SecureField("Confirm Password", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                        .accessibilityIdentifier("register_confirm_password_field")

                    if let passwordError = viewModel.passwordError {
                        Text(passwordError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("register_password_error")
                    }
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("register_error_message")
                    }
                }

                Section {
                    Button {
                        Task {
                            await viewModel.register()
                        }
                    } label: {
                        if viewModel.isLoading {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Create Account")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!viewModel.isFormValid || viewModel.isLoading)
                    .accessibilityIdentifier("register_submit_button")
                }
            }
            .accessibilityIdentifier("register_screen")
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    RegisterView()
}
