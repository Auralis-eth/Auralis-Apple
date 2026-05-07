//
//  NFTNewsfeedLoadingView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/24/25.
//

import AuralisPrimaryModels
import OSLog
import SwiftUI

struct NFTNewsfeedLoadingView: View {
    enum Size {
        case large
        case small
    }

    let itemsLoaded: Int?
    let total: Int?
    let phase: NFTService.RefreshPhase
    var size: Size = .large

    private var titleText: String {
        switch phase {
        case .idle, .fetching:
            return "Loading your collection..."
        case .processingMetadata:
            return "Preparing your NFTs..."
        case .persisting:
            return "Saving your library..."
        case .cleaningUp:
            return "Finishing up..."
        }
    }

    var body: some View {
        VStack {
            if size == .large {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                    .padding(.top)
            }
            HeadlineFontText(titleText)
                .lineLimit(2, reservesSpace: true)
                .padding(.top, 16)
            LoadingProgressView(total: total, itemsLoaded: itemsLoaded, phase: phase)
        }
        .padding(.vertical)
        .frame(maxWidth: size == .large ? .infinity : 200)
        .glassEffect(.clear.tint(.surface), in: .containerRelative)
    }
}

struct LoadingProgressView: View {
    private static let logger = Logger(subsystem: "Auralis", category: "NFTNewsfeedLoadingView")
    var total: Int?
    var itemsLoaded: Int?
    var phase: NFTService.RefreshPhase = .idle

    private var progressValue: Double {
        guard let total = total, let loaded = itemsLoaded, total > 0 else {
            return 0.0
        }

        if loaded < 0 {
            Self.logger.warning("itemsLoaded cannot be negative: \(loaded, privacy: .public)")
        } else if total < 0 {
            Self.logger.warning("total cannot be negative: \(total, privacy: .public)")
        }

        if loaded > total {
            return 1.0
        } else {
            return Double(loaded) / Double(total)
        }
    }

    private var isIndeterminate: Bool {
        switch phase {
        case .processingMetadata, .persisting, .cleaningUp:
            return true
        case .idle, .fetching:
            return total != nil && itemsLoaded == nil
        }
    }

    private var isLoading: Bool {
        return total != nil || itemsLoaded != nil
    }

    private var statusText: String {
        switch phase {
        case .processingMetadata(let itemCount):
            return "Found \(itemCount) NFTs. Getting them ready for your library."
        case .persisting(let itemCount):
            return "Adding \(itemCount) NFTs to your local library."
        case .cleaningUp(let itemCount):
            return "Refreshing \(itemCount) NFTs and cleaning up older items."
        case .idle, .fetching:
            break
        }

        if let loaded = itemsLoaded, let total = total {
            if loaded > total {
                return "Loaded \(total) items"
            } else {
                return "Loaded \(loaded) of \(total)"
            }
        } else if total != nil {
            return "Loading your collection..."
        } else {
            return "Preparing to load your collection..."
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                if isIndeterminate || progressValue < 0.00 {
                    // Indeterminate progress indicator
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.secondary)
                        .scaleEffect(1.5)
                } else {
                    // Determinate progress bar
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .tint(.secondary)
                        .frame(height: 8)
                        .padding(.horizontal)

                    // Progress percentage
                    HeadlineFontText("\(Int(progressValue * 100))%")
                        .fontWeight(.bold)
                }
            }

            // Status text
            SubheadlineFontText(statusText)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
