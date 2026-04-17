//
//  ProfileCardView.swift
//  Auralis
//
//  Created by Daniel Bell on 2/8/26.
//

import ImagePlayground
import SwiftUI

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
    @State private var activeAvatarRequestID = UUID()
    @State private var resolvedENSName: String?
    private let logic = HomeTabLogic()

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
                } else {
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
                .accessibilityLabel("Manage accounts")
                .accessibilityIdentifier("home.accounts.open")

                SystemImage("qrcode.viewfinder")
                    .accessibilityLabel("Scan wallet QR code")
            }
            .foregroundStyle(Color.accent)
            .font(.system(size: 30, weight: .medium))
        }
        .task(id: currentAddress) {
            await refreshAvatar()
            await refreshENSName()
        }
        .alert("Avatar Error", isPresented: $showAvatarErrorAlert, actions: {
            Button("Dismiss", role: .cancel) {
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

        if let resolved = await ensResolver.reverseLookup(address: requestedAddress, correlationID: nil),
           resolved.isForwardVerified {
            guard requestedAddress == currentAddress else { return }
            resolvedENSName = resolved.ensName
        }
    }

    func generateAvatarImage(style: AvatarStyle = .abstract, requestID: UUID? = nil) async {
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
        }
        catch ImageCreator.Error.notSupported {
            avatarImage = nil
            return
        }
        catch is CancellationError {
            return
        }
        catch {
            avatarErrorMessage = "Failed to generate avatar image. Please try again.\n\(error.localizedDescription)"
            showAvatarErrorAlert = true
            return
        }
    }

    private func fallbackAvatarImage(for address: String) -> UIImage? {
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let imageIndex = (Int(normalizedAddress.seedBytes[0]) % 8) + 1
        let suffix = String(format: "%02d", imageIndex)
        return UIImage(named: "testProfile-\(suffix)")
    }

    /// Build a deterministic avatar prompt array for the given address and optional style.
    /// - Parameters:
    ///   - address: Wallet address string; will be normalized.
    ///   - style: Avatar style: abstract, character, geometric (default: abstract)
    /// - Returns: Array of ImagePlaygroundConcept text atoms for avatar generation
    @discardableResult
    func avatarPrompt(address: String, style: AvatarStyle = .abstract) -> [ImagePlaygroundConcept] {
        let addr = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Cache key includes style and address
        let key = "\(addr)|\(style.rawValue)"
        if let cached = avatarPromptCache[key] {
            return cached
        }

        // Style descriptor atoms
        let styleAtoms: [String] = {
            switch style {
            case .abstract:
                return [
                "abstract",
                "colorful",
                "modern style"
            ]
            case .character:
                let characterSubjects = [
                    "dog",
                    "cat",
                    "penguin",
                    "robot",
                    "rabbit",
                    "turtle",
                    "wolf",
                    "fox",
                    "deer",
                    "bighorn sheep",
                    "buffalo",
                    "lion",
                    "tiger",
                    "giant panda",
                    "bengal tiger",
                    "african lion",
                    "red kangaroo",
                    "budgerigar",
                    "zebu",
                    "zebra"
                ]
                let seededIndex = Int(addr.seedBytes[7]) % characterSubjects.count
                return [
                    "vibrant colors",
                    characterSubjects[seededIndex]
                ]
            case .geometric: return [
                "geometric shapes",
                "symmetry",
                "vivid palette"
            ]
            }
        }()

        // Mood variants for avatar
        let moods = ["friendly", "mysterious", "energetic", "calm", "bold"]
        // Deterministic pick helper
        @inline(__always)
        func pick<T>(_ arr: [T], _ b: Int) -> T {
            arr[Int(addr.seedBytes[b]) % arr.count]
        }

        let moodAtom = pick(moods, 5)

        // Compose atoms
        var atoms: [String] = [
            "digital art",
            "high detail",
            "vibrant colors",
            "clean background",
            "sharp focus",
            "vector style"
        ]
        atoms.append(contentsOf: styleAtoms)
        atoms.append("mood \(moodAtom)")

        let concepts = atoms.map { ImagePlaygroundConcept.text($0) }
        avatarPromptCache[key] = concepts
        return concepts
    }
}
