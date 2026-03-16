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
    @Binding var avatarImage: UIImage?
    let onOpenAccountSwitcher: () -> Void
    @State private var isLoadingAvatar: Bool = false
    @State private var avatarErrorMessage: String? = nil
    @State private var showAvatarErrorAlert: Bool = false
    @State private var avatarPromptCache = [String: [ImagePlaygroundConcept]]()
    
    var body: some View {
        HStack(spacing: 12) {
            
            Group {
                if let avatarImage = avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.7), lineWidth: 2))
                } else {
                    // Placeholder avatar circle
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
            
            Spacer()
            VStack(alignment: .leading) {
                Title2FontText("HELLO")
                SecondaryText("\(currentAccount?.address.displayAddress ?? "")")
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
            .padding(.horizontal)
        }
        .task {
            if avatarImage == nil {
                isLoadingAvatar = true
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let idx = Int.random(in: 1...8)
                let suffix = String(format: "%02d", idx)

                if let assetImage = UIImage(named: "testProfile-\(suffix)") {
                    isLoadingAvatar = false
                    avatarImage = assetImage
                } else {
                    await generateAvatarImage(
                        style: .character
                    )
                }
            }
        }
        .onChange(of: currentAddress) { _, _ in
            Task {
                avatarImage = nil
                await generateAvatarImage()
            }
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
    
    func generateAvatarImage(style: AvatarStyle = .abstract) async {
        guard !currentAddress.isEmpty else {
            avatarImage = nil
            return
        }
        
        isLoadingAvatar = true
        defer { isLoadingAvatar = false }
        
        let prompts = avatarPrompt(address: currentAddress, style: style)
        
        do {
            let imageCreator = try await ImageCreator()
            
            // Generate only 1 avatar image with square aspect ratio
            let images = imageCreator.images(for: prompts, style: .illustration, limit: 1)
            
            for try await image in images {
                let uiImage = UIImage(cgImage: image.cgImage)
                avatarImage = uiImage
                break
            }
        }
        catch ImageCreator.Error.notSupported {
            avatarImage = nil
            return
        }
        catch {
            avatarErrorMessage = "Failed to generate avatar image. Please try again.\n\(error.localizedDescription)"
            showAvatarErrorAlert = true
            return
        }
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
                "modern style",
            ]
            case .character: return [
                "vibrant colors",
            ] + [[
                "dog",
                "cat",
                "penguin",
                "robot",
                "Rabbit",
                "Turtle",
                "Wolves",
                "Foxes",
                "Deer",
                "Bighorn Sheep",
                "Buffalo",
                "Lion",
                "Tiger",
                "Giant Panda",
                "Bengal Tiger",
                "African Lion",
                "Red Kangaroo",
                "budgerigar",
                "zebu",
                "zebra"
            ].randomElement() ?? "dog"]
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
