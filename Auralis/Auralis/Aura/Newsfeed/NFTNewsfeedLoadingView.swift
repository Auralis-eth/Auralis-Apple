//
//  NFTNewsfeedLoadingView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/24/25.
//

import SwiftUI

struct NFTNewsfeedLoadingView: View {
    enum Size {
        case large
        case small
    }

    let itemsLoaded: Int?
    let total: Int?
    var size: Size = .large

    var body: some View {
        VStack {
            if size == .large {
                ProgressView()
                    .scaleEffect(1.5)
                    .progressViewStyle(CircularProgressViewStyle(tint: .secondary))
                    .padding(.top)
            }
            HeadlineFontText("Loading NFTs...")
                .padding(.top, 16)
            LoadingProgressView(total: total, itemsLoaded: itemsLoaded)
        }
        .padding(.vertical)
        .frame(maxWidth: size == .large ? .infinity : 200)
        .glassEffect(.regular.tint(.surface.opacity(0.2)), in: .rect(cornerRadius: 32))
    }
}

struct LoadingProgressView: View {
    var total: Int? = nil
    var itemsLoaded: Int? = nil

    private var progressValue: Double {
        guard let total = total, let loaded = itemsLoaded, total > 0 else {
            return 0.0
        }

        if loaded < 0 {
            print("WARNING: itemsLoaded cannot be negative: \(loaded)")
        } else if total < 0 {
            print("WARNING: total cannot be negative: \(total)")
        }

        if loaded > total {
            return 1.0
        } else {
            return Double(loaded) / Double(total)
        }
    }

    private var isIndeterminate: Bool {
        return total != nil && itemsLoaded == nil
    }

    private var isLoading: Bool {
        return total != nil || itemsLoaded != nil
    }

    private var statusText: String {
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
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
