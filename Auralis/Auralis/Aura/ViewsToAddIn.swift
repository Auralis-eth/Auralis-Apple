//
//  ViewsToAddIn.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import SwiftUI


//======================================================
import SwiftUI

struct PasswordSignInView: View {
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var showingAlert: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background Image
                Image("aurora-1") // Replace with your background image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .overlay(
                        // Dark overlay for better text readability
                        Color.background.opacity(0.3)
                    )

                VStack(spacing: 0) {
                    // Top section with title and profile
                    VStack(spacing: 30) {
                        Spacer()

                        // Sign In Title
                        HStack {
                            Text("Sign In")
                                .font(.system(size: 42, weight: .light))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                        }
                        .padding(.leading, 30)



                        Spacer()
                    }
                    .frame(height: geometry.size.height * 0.55)

                    // Bottom form section
                    VStack(spacing: 25) {
                        VStack(spacing: 20) {
                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "lock")
                                        .foregroundStyle(Color.textSecondary)
                                        .font(.system(size: 30, weight: .medium))

                                    if isPasswordVisible {
                                        TextField("Password", text: $password)
                                            .font(.system(size: 16))
                                    } else {
                                        SecureField("Password", text: $password)
                                            .font(.system(size: 16))
                                    }

                                    Button(action: {
                                        isPasswordVisible.toggle()
                                    }) {
                                        Image(systemName: isPasswordVisible ? "eye" : "eye.slash")
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                }
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)

                                // Underline
                                Rectangle()
                                    .fill(Color.textSecondary.opacity(0.3))
                                    .frame(height: 1)
                            }
                            .padding(.horizontal, 30)
                        }

                        // Sign In Button
                        Button(action: {
                            // Handle sign in action
                            if password.isEmpty {
                                showingAlert = true
                            } else {
                                // Perform sign in logic here
                                print("Signing in with password: \(password)")
                            }
                        }) {
                            Text("SIGN IN")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.accent, Color.deepBlue.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(25)
                        }
                        .padding(.horizontal, 30)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        Color.textPrimary
                            .clipShape(
                                RoundedRectangle(cornerRadius: 30)
                            )
                    )
                    .frame(height: geometry.size.height * 0.45)
                }
            }
        }
        .ignoresSafeArea()
        .alert("Password Required", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter your password to continue.")
        }
    }
}

//======================================================

struct MusicPlayerView: View {
    //var musicNFTs: [NFT] = [] {
//        nftMetaData.filter {
//            guard let metaData = $0.metadata else {
//                return false
//            }
//
//            return metaData.audioUrl != nil || ($0.nftBaseData.tokenUri?.hasSuffix(".mp3") ?? false) || ($0.nftBaseData.tokenUri?.hasSuffix(".wav") ?? false) || metaData.audioURI != nil || metaData.losslessAudio != nil || metaData.audio != nil
//        }
//    }

    @State private var progress: Double = 0.65
    @State private var isPlaying = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.red.opacity(0.8),
                    Color.orange.opacity(0.6),
                    Color.blue.opacity(0.4),
                    Color.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Album Art Section
                VStack(spacing: 16) {
                    // Album artwork with rounded corners
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.pink.opacity(0.3), Color.purple.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 280, height: 280)
                        .overlay(
                            VStack {
                                Spacer()
                                Image(systemName: "person.fill")
                                    .font(.system(size: 60))
                                    .foregroundStyle(Color.textPrimary.opacity(0.7))
                                Text("UNFOLDING")
                                    .font(.title)
                                    .fontWeight(.light)
                                    .foregroundStyle(Color.textPrimary)
                                    .tracking(2)
                                Spacer()
                            }
                        )

                    // Song info
                    VStack(spacing: 4) {
                        Text("Unfolding")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.textPrimary)

                        Text("Lindsey Stirling & Rachel Platten")
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary.opacity(0.7))
                    }
                }
                .padding(.horizontal, 40)

                Spacer()

                // Progress bar and time
                VStack(spacing: 8) {
                    // Progress bar
                    HStack {
                        Slider(value: $progress, in: 0...1, step: 0.25)
                            .accentColor(.white)
                            .padding(.horizontal, 40)
                    }

                    // Time labels
                    HStack {
                        Text("2:09")
                            .font(.caption)
                            .foregroundStyle(Color.textPrimary.opacity(0.7))
                        Spacer()
                        Text("-1:30")
                            .font(.caption)
                            .foregroundStyle(Color.textPrimary.opacity(0.7))
                    }
                    .padding(.horizontal, 40)
                }

                // Control buttons
                HStack(spacing: 50) {
                    Button(action: {}) {
                        Image(systemName: "star")
                            .font(.title2)
                            .foregroundStyle(Color.textPrimary)
                    }

                    Button(action: {}) {
                        Image(systemName: "backward.fill")
                            .font(.title)
                            .foregroundStyle(Color.textPrimary)
                    }

                    Button(action: { isPlaying.toggle() }) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundStyle(Color.textPrimary)
                    }

                    Button(action: {}) {
                        Image(systemName: "forward.fill")
                            .font(.title)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
                .padding(.vertical, 20)

                // Audio output selector
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Color.textPrimary.opacity(0.8))
                    Text("iPhone Speaker")
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary.opacity(0.8))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.textPrimary.opacity(0.5))
                        .font(.caption)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 12)

                Spacer()

                musicPlaybackView

            }
//            .tabViewBottomAccessory {
//                musicPlaybackView
//            }
        }
    }

    var musicPlaybackView: some View {
//        @Environment(\.tabViewBottomAccessoryPlacement) var placement
//      if placement == .inline 
        HStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.8))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "moon.stars.fill")
                        .foregroundStyle(Color.textPrimary)
                        .font(.title3)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("White Noise")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
                Text("Naty's Room")
                    .font(.caption)
                    .foregroundStyle(Color.textPrimary.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.surface.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.textPrimary.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}

