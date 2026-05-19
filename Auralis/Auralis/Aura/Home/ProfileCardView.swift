//
//  ProfileCardView.swift
//  Auralis
//
//  Created by Daniel Bell on 2/8/26.
//

import AccountsFeature
import ENS
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import ImagePlayground
import SwiftUI
import AuraUI

struct ProfileCardView: View {
    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    let currentChain: Chain
    let scopedNFTCount: Int
    @Binding var avatarImage: UIImage?
    let ensResolver: any ENSResolving
    let onOpenAccountSwitcher: () -> Void
    @State private var isLoadingAvatar: Bool = false
    @State private var avatarErrorMessage: String?
    @State private var showAvatarErrorAlert: Bool = false
    @State private var avatarPromptCache = [String: [ImagePlaygroundConcept]]()
    @State private var avatarPromptCacheOrder: [String] = []
    @State private var activeAvatarRequestID = UUID()
    @State private var resolvedENSName: String?
    private let logic = HomeTabLogic()
    private let avatarArtworkSupport = ProfileAvatarArtworkSupport()
    private let ensDisplayResolver = ProfileENSDisplayResolver()
    private let maxAvatarPromptCacheEntries = 24

    private var summary: HomeAccountSummaryPresentation {
        logic.accountSummaryPresentation(
            currentAccount: currentAccount,
            currentAddress: currentAddress,
            currentChain: currentChain,
            scopedNFTCount: scopedNFTCount
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Group {
                if let avatarImage = avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 2))
                } else {
                    Circle()
                        .fill(Color.textSecondary.opacity(0.3))
                }
            }
            .frame(width: 96, height: 96)
            .overlay {
                if isLoadingAvatar {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                } else if avatarImage == nil {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.deepBlue)
                        .padding(18)
                }
            }
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Title2FontText(summary.title)
                    if let resolvedENSName {
                        SecondaryText(resolvedENSName)
                    }
                    SecondaryText(summary.addressLine)
                    SecondaryCaptionFontText(summary.chainTitle)
                }

                HStack(spacing: 8) {
                    AuraPill(summary.chainTitle, systemImage: "globe", emphasis: .accent)
                    AuraPill(summary.trackedNFTLabel, systemImage: "square.stack.3d.up", emphasis: .neutral)
                }

                if let lastActivityLabel = summary.lastActivityLabel {
                    SecondaryCaptionFontText(lastActivityLabel)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: onOpenAccountSwitcher) {
                    SystemImage("square.and.pencil")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Manage accounts"))
                .accessibilityIdentifier("home.accounts.open")
            }
            .foregroundStyle(Color.accent)
            .font(.system(size: 30, weight: .medium))
        }
        .task(id: currentAddress) {
            await refreshAvatar()
            await refreshENSName()
        }
        .alert(String(localized: "Avatar Error"), isPresented: $showAvatarErrorAlert, actions: {
            Button(String(localized: "Dismiss"), role: .cancel) {
                showAvatarErrorAlert = false
            }
        }, message: {
            if let avatarErrorMessage = avatarErrorMessage {
                Text(avatarErrorMessage)
            }
        })
        .padding()
    }

    // MARK: - Avatar Image Generation

    private func refreshAvatar() async {
        let requestID = UUID()
        activeAvatarRequestID = requestID
        avatarImage = nil

        guard !currentAddress.isEmpty else {
            isLoadingAvatar = false
            return
        }

        isLoadingAvatar = true
        if let assetImage = fallbackAvatarImage(for: currentAddress) {
            guard requestID == activeAvatarRequestID else { return }
            avatarImage = assetImage
            isLoadingAvatar = false
            return
        }

        await generateAvatarImage(style: .character, requestID: requestID)
    }

    private func refreshENSName() async {
        resolvedENSName = nil
        let requestedAddress = currentAddress

        guard !requestedAddress.isEmpty else {
            return
        }

        if let cached = await ensResolver.cachedReverseResolution(forAddress: requestedAddress),
           cached.isForwardVerified {
            guard requestedAddress == currentAddress else { return }
            resolvedENSName = cached.ensName

            if !cached.isStale {
                return
            }
        }

        if let resolved = await ensDisplayResolver.resolveName(for: requestedAddress, using: ensResolver) {
            guard requestedAddress == currentAddress else { return }
            resolvedENSName = resolved
        }
    }

    private func generateAvatarImage(style: AvatarStyle = .abstract, requestID: UUID? = nil) async {
        guard !currentAddress.isEmpty else {
            avatarImage = nil
            return
        }

        isLoadingAvatar = true
        defer {
            if requestID == nil || requestID == activeAvatarRequestID {
                isLoadingAvatar = false
            }
        }

        let prompts = avatarPrompt(address: currentAddress, style: style)

        do {
            let imageCreator = try await ImageCreator()

            // Generate only 1 avatar image with square aspect ratio
            let images = imageCreator.images(for: prompts, style: .illustration, limit: 1)

            for try await image in images {
                try Task.checkCancellation()
                guard requestID == nil || requestID == activeAvatarRequestID else { return }
                let uiImage = UIImage(cgImage: image.cgImage)
                avatarImage = uiImage
                break
            }
        } catch ImageCreator.Error.notSupported {
            avatarImage = nil
            return
        } catch is CancellationError {
            return
        } catch {
            avatarErrorMessage = String(
                localized: "Failed to generate avatar image. Please try again.\n\(error.localizedDescription)"
            )
            showAvatarErrorAlert = true
            return
        }
    }

    private func fallbackAvatarImage(for address: String) -> UIImage? {
        guard let assetName = avatarArtworkSupport.fallbackAvatarAssetName(for: address) else {
            return nil
        }

        return UIImage(named: assetName)
    }

    /// Build a deterministic avatar prompt array for the given address and optional style.
    /// - Parameters:
    ///   - address: Wallet address string; will be normalized.
    ///   - style: Avatar style: abstract, character, geometric (default: abstract)
    /// - Returns: Array of ImagePlaygroundConcept text atoms for avatar generation
    private func avatarPrompt(address: String, style: AvatarStyle = .abstract) -> [ImagePlaygroundConcept] {
        let addr = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let key = "\(addr)|\(style.rawValue)"
        if let cached = avatarPromptCache[key] {
            return cached
        }

        let concepts = avatarArtworkSupport
            .promptAtoms(address: addr, style: style)
            .map(ImagePlaygroundConcept.text)
        cacheAvatarPrompts(concepts, for: key)
        return concepts
    }

    private func cacheAvatarPrompts(_ concepts: [ImagePlaygroundConcept], for key: String) {
        avatarPromptCache[key] = concepts
        avatarPromptCacheOrder.removeAll { $0 == key }
        avatarPromptCacheOrder.append(key)

        while avatarPromptCache.count > maxAvatarPromptCacheEntries,
              let eldestKey = avatarPromptCacheOrder.first {
            avatarPromptCacheOrder.removeFirst()
            avatarPromptCache.removeValue(forKey: eldestKey)
        }
    }
}
