//
//  AddressEntryView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI
import SwiftData
// Uses GPSpacing & typography helpers from GuestPassTokens.swift
public enum GPSpacing {
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
}

struct AddressInputView: View {
    @State private var address: String = ""
    @State private var showingAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @Environment(\.modelContext) private var modelContext
    @Binding var currentAccount: EOAccount?

    private func selectDemo(address: String) {
        self.address = address
        handleSubmit()
    }

    private var isAddressValid: Bool {
        extractEthereumAddress(address) != nil
    }

    var body: some View {
        VStack(alignment: .center) {
            // Header
            VStack(spacing: 6) {
                Title2FontText("Check in with your Ethereum address")
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                SubheadlineFontText("Paste an address or ENS name, or scan a QR code to get started.")
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                QRScannerView(account: $currentAccount)
                    .transition(.opacity)
                AddressTextField(address: $address)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 18)
            
            Button {
                handleSubmit()
            } label: {
                Text("Enter Auralis")
                    .foregroundStyle(Color.textPrimary)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.accent.gradient, in: .capsule)
            }
            .padding(.horizontal, 30)
            
            HStack {
                Rectangle()
                    .fill(Color.textSecondary.opacity(0.2))
                    .frame(width: 72, height: 1)
                SubheadlineFontText("Or explore Auralis as a guest")
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle()
                    .fill(Color.textSecondary.opacity(0.2))
                    .frame(width: 72, height: 1)
            }
            .padding(.vertical)
            VStack(spacing: 6) {
                Title2FontText("Guest passes")
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                SubheadlineFontText("Try Auralis with curated public collections.")
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .fixedSize(horizontal: false, vertical: true)
            
            GuestPassCarousel(items: DemoAccount.accounts) { acct in
                selectDemo(address: acct.address)
            }
            .padding(.bottom, GPSpacing.s)
            
        }
        .glassEffect(.clear.tint(.surface), in: .rect(cornerRadius: 30))
        .safeAreaPadding(15)
        .transition(.scale.combined(with: .opacity))
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .submitLabel(.go)
        .onSubmit {
            handleSubmit()
        }
    }

    private func handleSubmit() {
        guard !address.isEmpty else {
            showAlert(title: "Address Required",
                      message: "Please enter your Ethereum address or use a guest pass.")
            return
        }

        guard let normalized = extractEthereumAddress(address) else {
            showAlert(title: "Invalid Address",
                      message: "That doesn’t look like a valid address or ENS. Try again or use a guest pass.")
            return
        }

        let eoAccount = EOAccount(address: normalized, access: .readonly)
        modelContext.insert(eoAccount)
        do {
            try modelContext.save()
            address = ""
            currentAccount = eoAccount
        } catch {
            showAlert(title: "Save Failed",
                      message: "Failed to save account: \(error.localizedDescription)")
        }
    }

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }

    private func extractEthereumAddress(_ input: String) -> String? {
        let address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        let addressPattern = #"^0x[a-fA-F0-9]{40}$"#
        if let match = address.range(of: addressPattern, options: .regularExpression) {
            return String(address[match])
        }
        // If the input is a 40-character hex string without the 0x prefix, prepend it and accept.
        let noPrefixPattern = #"^[a-fA-F0-9]{40}$"#
        if let match = address.range(of: noPrefixPattern, options: .regularExpression) {
            return "0x" + String(address[match])
        }
        return nil
    }
}

struct AddressTextField: View {
    @Binding var address: String

    var body: some View {
        TextField(
            "Ethereum Address",
            text: $address,
            prompt: Text("0x… or ENS name").foregroundColor(.textSecondary)
        )
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .font(.body)
            .scrollContentBackground(.hidden)
            .foregroundStyle(Color.textSecondary)
    }
}

struct GuestPassCarousel: View {
    let items: [DemoAccount]
    let select: (DemoAccount) -> Void

    var body: some View {
            ScrollView(.horizontal) {
                HStack(spacing: GPSpacing.m) {
                    ForEach(items) { acct in
                        LiquidGlassCard(account: acct, onTap: { select(acct) })
                        .padding(.vertical, 8)
                        .glassEffect(.clear.tint(.surface), in: .rect(cornerRadius: 30))
                        .padding()
                            .id(acct.id)
                            .accessibilityLabel(Text(acct.title))
                            .accessibilityHint(Text("Opens Auralis with a demo account"))
                }
                .scrollTargetLayout()
//                .contentMargins(.horizontal, GPSpacing.xl, for: .scrollContent)
            }
            .scrollIndicators(.hidden)
//            .scrollTargetBehavior(.paging)
        }
    }
}

// MARK: - Guest Pass Card Support

struct LiquidGlassCard: View {
    let account: DemoAccount
    var onTap: (() -> Void)? = nil

    @State private var isAnimating = false
    @State private var dragOffset: CGSize = .zero

    private var shortAddress: String {
        let trimmed = account.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = trimmed.prefix(6)
        let end = trimmed.suffix(4)
        return "\(start)…\(end)"
    }

    var body: some View {
        // The Card
        VStack(spacing: 10) {
            // Header Icons + Pill
            HStack(alignment: .center) {
                    SystemImage(account.role.image)
                    .font(.system(size: 20))
                Spacer()
                if let ens = account.ens {
                    Caption2FontText(ens.uppercased())
                        .textCase(.uppercase)
                        .monospaced()
                }
                Spacer()
                
                // Metadata row (compact)
                HStack {
                    ForEach(account.metadata) { md in
                            SystemImage(md.systemImage)
                                .font(.footnote)
                                .foregroundStyle(Color.textPrimary.opacity(0.75))
                    }
                }
            }
            .foregroundStyle(Color.textPrimary.opacity(0.85))
            .padding(.top, 20)
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            // Main Text
            VStack {
                // Primary title (monospaced heavy)
                Text(account.title)
                    .font(.largeTitle)
                    .fontWeight(.black)
                    .monospaced()
                    .tracking(2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.textPrimary)

                // Secondary title (thin monospaced)
                Text(account.subtitle)
                    .font(.body)
                    .fontWeight(.thin)
                    .monospaced()
                    .tracking(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal)

            Spacer(minLength: 0)

            // Footer Data
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ADDRESS")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                    Text(shortAddress)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityLabel("Ethereum address \(account.address)")
                }

                Spacer()

                // Faux Barcode
                Image(systemName: "barcode")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 40)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.bottom, 30)
            .padding(.horizontal, 24)
        }
        .frame(width: 320, height: 500)
        .background {
            // 1. The Glass Material
            RoundedRectangle(cornerRadius: 30)
                .fill(.ultraThinMaterial)
                .opacity(0.9)
        }
        .overlay {
            // 2. The Liquid Shimmer Overlay
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 30)
                        .stroke(
                            LinearGradient(
                                colors: [.clear, .accent.opacity(0.8), .white, .accent.opacity(0.8), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        // Animate the gradient mask
                        .mask(
                            LinearGradient(
                                colors: [.clear, .black, .clear],
                                startPoint: isAnimating ? .topLeading : .bottomTrailing,
                                endPoint: isAnimating ? .bottomTrailing : .topLeading
                            )
                            .frame(width: 800, height: 800)
                            .offset(x: isAnimating ? 200 : -200, y: isAnimating ? 200 : -200)
                        )
                )
        }
        .overlay {
            // 3. Inner White Specular Highlight (Liquid edge effect)
            RoundedRectangle(cornerRadius: 30)
                .stroke(.white.opacity(0.5), lineWidth: 1)
                .blendMode(.overlay)
                .blur(radius: 1)
        }
        .shadow(color: .accent.opacity(0.4), radius: 20, x: 0, y: 10)
        .rotation3DEffect(
            .degrees(Double(dragOffset.width) / 15),
            axis: (x: 0, y: 1, z: 0)
        )
        .rotation3DEffect(
            .degrees(Double(dragOffset.height) / 15),
            axis: (x: 1, y: 0, z: 0)
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        dragOffset = .zero
                    }
                }
        )
        .contentShape(.rect)
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}
