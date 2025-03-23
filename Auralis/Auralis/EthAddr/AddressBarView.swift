import SwiftUI

struct AddressBarView: View {
    @Binding var address: String
    @State private var isLoading: Bool = false
    @State private var isEditing: Bool = false
    var populateNFTs: (() async -> Void)? = nil

    // Format the address for display (abbreviated)
    private var displayAddress: String {
        if !isEditing && address.count > 10 {
            let start = address.prefix(6)
            let end = address.suffix(4)
            return "\(start)...\(end)"
        }
        return address
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wallet.pass")
                .foregroundColor(.textSecondary)  // Changed from .secondary to app's textSecondary
                .font(.system(size: 16, weight: .medium))
                .padding(.leading, 4)

            if isEditing {
                // Full address when editing
                TextField("Enter wallet address", text: $address)
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit {
                        isEditing = false
                        submitAddress()
                    }
                    .onAppear {
                        // Ensure keyboard is shown when editing starts
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            UIApplication.shared.sendAction(#selector(UIResponder.becomeFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
            } else {
                // Abbreviated address when not editing
                Text(displayAddress)
                    .font(.system(size: 15))
                    .foregroundColor(.textPrimary)
                    .onTapGesture {
                        isEditing = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                if isEditing {
                    isEditing = false
                }
                submitAddress()
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                            .tint(.secondary)  // Added tint for the progress indicator
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.secondary)  // Changed from .blue to app's secondary (teal green)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, 4)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surface)  // Changed from Color(.systemBackground) to app's surface color
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.deepBlue.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func submitAddress() {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isLoading = true

        Task {
            await populateNFTs?()
            isLoading = false
        }
    }
}
