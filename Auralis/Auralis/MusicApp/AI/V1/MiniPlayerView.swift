//
//  MiniPlayerView.swift
//  Auralis
//
//  Created by Daniel Bell on 9/15/25.
//

import SwiftUI
// A) move POC audio controls and display
    // 1) now playing view
    //      album art   (NEW/ADD)
    //      title       (NEW/ADD)
    //      artist      (NEW/ADD)
    //      forward
    //      reverse
    //      progress/seek bar
    // 2) mini player view
    //      album art   (NEW/ADD)
    //      title       (NEW/ADD)
    //      artist      (NEW/ADD)
    //      forward
// 420) fix the design/layout/UI apearance
// 710) address the placement enviroment property

// MARK: - Mini Player (bottom accessory)
struct MiniPlayerView: View {
    @ObservedObject var audioEngine: AudioEngine
    /**
     # TabViewBottomAccessoryPlacement Environment Value
     
     The `@Environment(\.tabViewBottomAccessoryPlacement)` environment value is a **SwiftUI property introduced in iOS 26**
     that provides information about the current placement state of a tab view's bottom accessory. This environment value
     works in conjunction with the new `.tabViewBottomAccessory` modifier to create adaptive UI components that respond
     to tab bar minimization behavior.
     
     ## Placement States
     
     The `tabViewBottomAccessoryPlacement` environment value returns a `TabViewBottomAccessoryPlacement` enum with
     possible states:
     
     - `.inline`: The accessory is placed inline with the bottom tab bar, integrating with the tab bar
     - `.expanded`: The accessory is displayed expanded above the tab bar with its own layout when the tab bar is
       minimized or in certain scroll states
     - `nil`: No specific placement is defined (accessory rendered outside supported TabView context)
     
     By checking `placement`, your accessory view can adjust its UI accordingly — show more detail when expanded,
     simplify when inline, or hide entirely when `nil`.
     
     ## Recommended Best Practices
     
     - **Provide a safe default UI**: Render a fallback appearance or minimal content instead of assuming expanded or
       inline states
     - **Avoid critical logic on nil**: Do not trigger navigation, animations, or essential UI behaviors when placement
       is nil. Use a simple placeholder or hide the accessory
     - **Debug context usage**: If placement is unexpectedly nil, verify that the accessory is inside a
       `.tabViewBottomAccessory` within a properly configured TabView, and isn't wrapped in a view hierarchy
       that breaks environment propagation
     */
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @State private var showNowPlaying: Bool = false

    private var progressFraction: Double {
        guard let t = audioEngine.currentTrack, t.duration > 0 else { return 0 }
        return audioEngine.progress / t.duration
    }

    var body: some View {
        Group {
//            if audioEngine.currentTrack == nil {
//                EmptyView()
//            } else {
                content
                    .onTapGesture {
                        showNowPlaying = true
                    }
                    .sheet(isPresented: $showNowPlaying) {
                        NowPlayingView(audioEngine: audioEngine)
                    }
//            }
        }
        .accessibilityElement(children: .contain)
    }

    private var content: some View {
        VStack {
            HStack(spacing: 12) {
                // album art / icon
                RoundedRectangle(cornerRadius: 6)
                    .frame(width: placement == .expanded ? 44 : 36, height: placement == .expanded ? 44 : 36)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: placement == .expanded ? 20 : 16))
                            .padding(6)
                    )
                
                // title / artist
                VStack(alignment: .leading, spacing: 2) {
                    Text(audioEngine.currentTrack?.title ?? "Unknown Title")
                        .font(placement == .expanded ? .subheadline.bold() : .subheadline)
                        .lineLimit(1)
                    if placement == .expanded {
                        Text(audioEngine.currentTrack?.artist ?? "Unknown Artist")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                
                // playback controls
                HStack(spacing: 8) {
                    switch audioEngine.playbackState {
                    case .loading:
                        Button(action: audioEngine.pause) {
                            Image(systemName: "pause.fill")
                                .font(.title3)
                        }
                        .disabled(true) // disable the button
                        .overlay {
                            ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                        }
                    case .playing:
                        Button(action: audioEngine.pause) {
                            Image(systemName: "pause.fill")
                                .font(.title3)
                        }
                    case .paused:
                        Button {
                            try? audioEngine.resume()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.title3)
                        }
                    case .stopped:
                        Button {
                            try? audioEngine.play()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.title3)
                        }
                    }
                    Button(action: audioEngine.playNext) {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                    }
                }
                .buttonStyle(.glass)
            }
            
            // compact progress indicator
            ProgressView(value: progressFraction)
                .frame(maxWidth:.infinity)

        }
//        .glassEffect(.clear)
    }
}
