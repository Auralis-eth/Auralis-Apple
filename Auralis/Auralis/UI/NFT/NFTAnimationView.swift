//
//  NFTAnimationView.swift
//  Auralis
//
//  Created by Daniel Bell on 3/3/25.
//

import AVKit
import SwiftUI
import WebKit

struct BasicWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
}

struct NFTAnimationView: View {
    var animation: NFTAnimation?
    var image: URL? {
        animation?.animations?.first
    }
    var details: [String: Any]? {
        animation?.details
    }
    var isIPFS: Bool {
        animation?.source == .ipfs
    }
    var isVideo: Bool {
        (details != nil && !(details?.isEmpty ?? true)) || (image?.isVideoMP4 ?? false) || isIPFS
    }
    var body: some View {
        if let image {
            if isVideo {
                VideoPlayer(
                    player: AVPlayer(url: image)
                )
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
            } else if animation?.source == .website {
                BasicWebView(url: image)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
            } else {
                CachedAsyncImage(url: image)
            }

        } else {
            EmptyView()
        }
    }
}
