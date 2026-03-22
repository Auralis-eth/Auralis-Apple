//
//  GalleryGrid.swift
//  Auralis
//
//  Created by Daniel Bell on 10/20/25.
//

import SwiftUI

/// New GalleryGrid View added as requested
struct GalleryGrid: View {
    let images: [UIImage]
    @Binding var selectedScene: AuroraScene
    let onPick: (UIImage) -> Void
    let onRegenerate: (() async -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if onRegenerate != nil {
                HStack(spacing: 12) {
                    Picker("Scene", selection: $selectedScene) {
                        ForEach(AuroraScene.allCases) { scene in
                            Text(scene.label).tag(scene)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Button {
                        Task {
                            await onRegenerate?()
                        }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .disabled(onRegenerate == nil)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()
            }

            if images.isEmpty {
                VStack(spacing: 24) {
                    SystemImage("photo.on.rectangle")
                        .font(.system(size: 60))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Text("No images to select")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.offset) { idx, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 110)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .cornerRadius(12)
                                .onTapGesture {
                                    onPick(image)
                                }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

