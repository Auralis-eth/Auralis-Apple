//
//  NFTNewsfeedLoadingView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/24/25.
//

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
            return "Loading NFTs..."
        case .processingMetadata:
            return "Processing Metadata..."
        case .persisting:
            return "Saving Collection..."
        case .cleaningUp:
            return "Finalizing Refresh..."
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
            return "Fetched \(itemCount) NFTs. Parsing metadata before save."
        case .persisting(let itemCount):
            return "Fetched \(itemCount) NFTs. Writing them into your local library."
        case .cleaningUp(let itemCount):
            return "Fetched \(itemCount) NFTs. Cleaning up stale items and wrapping up."
        case .idle, .fetching:
            break
        }

        if let loaded = itemsLoaded, let total = total {
            if loaded > total {
                return "\(total) loaded"
            } else {
                return "\(loaded) of \(total) loaded"
            }
        } else if total != nil {
            return "Loading..."
        } else {
            return "Waiting to start..."
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
