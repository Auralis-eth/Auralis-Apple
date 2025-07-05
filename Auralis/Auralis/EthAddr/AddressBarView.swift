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
            SecondaryTextSystemImage( "wallet.pass")
                .font(.system(size: 16, weight: .medium))
                .padding(.leading, 4)
                .accessibilityHidden(true)

            if isEditing {
                // Full address when editing
                TextField("Enter wallet address", text: $address)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.textPrimary)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit {
                        isEditing = false
                        submitAddress()
                    }
            } else {
                // Abbreviated address when not editing
                SystemFontText(text: displayAddress, size: 15)
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
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.8)
                        .tint(.secondary)  // Added tint for the progress indicator
                        .frame(width: 28, height: 28)
                } else {
                    SecondarySystemImage( "arrow.right.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .accessibilityLabel("Submit")
                }

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
