import AuraUI
import NFTKit
import SwiftUI

public struct NFTLibraryLoadingView: View {
    public enum Size {
        case large
        case small
    }

    public let itemsLoaded: Int?
    public let total: Int?
    public let phase: NFTServiceRefreshPhase
    public var size: Size

    public init(itemsLoaded: Int?, total: Int?, phase: NFTServiceRefreshPhase, size: Size = .large) {
        self.itemsLoaded = itemsLoaded
        self.total = total
        self.phase = phase
        self.size = size
    }

    private var titleText: String {
        switch phase {
        case .idle, .fetching:
            "Loading your collection..."
        case .processingMetadata:
            "Preparing your NFTs..."
        case .persisting:
            "Saving your library..."
        case .cleaningUp:
            "Finishing up..."
        }
    }

    public var body: some View {
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
            NFTLibraryLoadingProgressView(total: total, itemsLoaded: itemsLoaded, phase: phase)
        }
        .padding(.vertical)
        .frame(maxWidth: size == .large ? .infinity : 200)
        .background {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.clear.tint(.surface), in: .containerRelative)
            } else {
                Color.surface.opacity(0.82)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

public struct NFTLibraryLoadingProgressView: View {
    public var total: Int?
    public var itemsLoaded: Int?
    public var phase: NFTServiceRefreshPhase

    public init(total: Int?, itemsLoaded: Int?, phase: NFTServiceRefreshPhase = .idle) {
        self.total = total
        self.itemsLoaded = itemsLoaded
        self.phase = phase
    }

    private var progressValue: Double {
        guard let total, let itemsLoaded, total > 0 else {
            return 0.0
        }

        return min(Double(itemsLoaded) / Double(total), 1.0)
    }

    private var isIndeterminate: Bool {
        switch phase {
        case .processingMetadata, .persisting, .cleaningUp:
            true
        case .idle, .fetching:
            total != nil && itemsLoaded == nil
        }
    }

    private var isLoading: Bool {
        total != nil || itemsLoaded != nil
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

        if let loaded = itemsLoaded, let total {
            return loaded > total ? "Loaded \(total) items" : "Loaded \(loaded) of \(total)"
        } else if total != nil {
            return "Loading your collection..."
        } else {
            return "Preparing to load your collection..."
        }
    }

    public var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                if isIndeterminate {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.secondary)
                        .scaleEffect(1.5)
                } else {
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .tint(.secondary)
                        .frame(height: 8)
                        .padding(.horizontal)

                    HeadlineFontText("\(Int(progressValue * 100))%")
                        .fontWeight(.bold)
                }
            }

            SubheadlineFontText(statusText)
                .lineLimit(2, reservesSpace: true)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
