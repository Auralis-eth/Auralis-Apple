////
////  MusicApp.swift
////  Auralis
////
////  Created by Daniel Bell on 3/23/25.
////
//
//
//import SwiftUI
//
//struct MusicApp: View {
//    @StateObject private var audioPlayer = AudioPlayerManager()
//    var musicNFTs: [NFT]
//
//    var body: some View {
//        VStack {
//            if musicNFTs.isEmpty {
//                Text("No audio NFTs found")
//            } else {
//                VStack {
//                    ForEach(musicNFTs) { nft in
//                        Card3D(cardColor: .surface) {
//                            HStack {
//                                // Show NFT name or "Unknown" if name is not available
//                                Text(nft.metadata?.name ?? "Unknown")
//                                    .lineLimit(1)
//                                    .truncationMode(.tail)
//                                    .frame(maxWidth: .infinity, alignment: .leading)
//                                    .foregroundColor(.textSecondary)
//
//                                if let parsedData = nft.metadata, let audioUrl = parsedData.audioUrl ?? parsedData.audioURI ?? parsedData.losslessAudio ?? parsedData.audio {
//                                    // Play/Pause Button
//                                    Button(action: {
//                                        Task {
//                                            if audioPlayer.isPlaying && audioPlayer.currentUrl == audioUrl {
//                                                audioPlayer.pause()
//                                            } else {
//                                                await audioPlayer.setupAudio(with: audioUrl)
//                                                audioPlayer.play()
//                                            }
//                                        }
//                                    }) {
//                                        Image(systemName: audioPlayer.isPlaying && audioPlayer.currentUrl == audioUrl
//                                              ? "pause.circle.fill" : "play.circle.fill")
//                                        .font(.title2)
//                                        .foregroundColor( audioPlayer.isPlaying && audioPlayer.currentUrl == audioUrl
//                                                          ? .secondary : .deepBlue)
//                                        .accessibilityLabel( audioPlayer.isPlaying && audioPlayer.currentUrl == audioUrl
//                                                             ? "pause" : "play")
//                                    }
//                                } else {
//                                    // Disabled play button if no audio URL available
//                                    Image(systemName: "play.circle.fill")
//                                        .font(.title2)
//                                        .foregroundColor(.gray)
//                                        .opacity(0.5)
//                                }
//                            }
//                        }
//                    }
//                }
//            }
//            VStack(spacing: 20) {
//                Text("Music Player")
//                    .font(.title)
//                    .fontWeight(.bold)
//
//                if audioPlayer.isPlaying {
//                    Image(systemName: "waveform")
//                        .font(.system(size: 100))
//                        .foregroundColor(.blue)
//                } else {
//                    Image(systemName: "waveform.slash")
//                        .font(.system(size: 100))
//                        .foregroundColor(.gray)
//                }
//
//                HStack(spacing: 30) {
//                    Button {
//                        if audioPlayer.isPlaying {
//                            audioPlayer.pause()
//                        } else {
//                            audioPlayer.play()
//                        }
//                    } label: {
//                        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
//                            .font(.system(size: 50))
//                    }
//                    .disabled(musicNFTs.isEmpty)
//
//                    Button {
//                        audioPlayer.stop()
//                    } label: {
//                        Image(systemName: "stop.circle.fill")
//                            .font(.system(size: 50))
//                    }
//                    .disabled(musicNFTs.isEmpty)
//                }
//
//                if let error = audioPlayer.errorMessage {
//                    Text(error)
//                        .foregroundColor(.red)
//                        .padding()
//                }
//            }
//        }
//        .padding()
//    }
//}
//
