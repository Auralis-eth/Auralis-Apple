//
//  GalleryGrid.swift
//  Auralis
//
//  Created by Daniel Bell on 10/20/25.
//

import SwiftUI
import AuraUI

/// New GalleryGrid View added as requested
struct GalleryGrid: View {
    let images: [UIImage]
    @Binding var selectedScene: AuroraScene
    let onPick: (UIImage) -> Void
    let onRegenerate: (() async -> Void)?
    @State private var regenerateTask: Task<Void, Never>?
    @State private var selectedImageID: ObjectIdentifier?
    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 110

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
                        regenerateTask?.cancel()
                        regenerateTask = Task {
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
                        .accessibilityHidden(true)
                    Text(String(localized: "No images to select"))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding()
            } else {
                ScrollView {
                    let scaledThumbnailSize = min(thumbnailSize, 180)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: scaledThumbnailSize), spacing: 8)], spacing: 8) {
                        ForEach(Array(images.enumerated()), id: \.element.auralisObjectIdentifier) { index, image in
                            let imageID = image.auralisObjectIdentifier
                            let isSelected = selectedImageID == imageID || images.count == 1

                            Button {
                                selectedImageID = imageID
                                onPick(image)
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: scaledThumbnailSize)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(.rect(cornerRadius: 12))
                                    .accessibilityHidden(true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Generated \(selectedScene.label) image, option \(index + 1) of \(images.count)")
                            .accessibilityHint("Selects this image for the home background")
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding()
                }
            }
        }
        .onDisappear {
            regenerateTask?.cancel()
            regenerateTask = nil
        }
    }
}

private extension UIImage {
    var auralisObjectIdentifier: ObjectIdentifier {
        ObjectIdentifier(self)
    }
}
