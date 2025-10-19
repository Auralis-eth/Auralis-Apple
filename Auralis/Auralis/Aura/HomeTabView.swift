import SwiftUI
import SwiftData
import ImagePlayground

struct HomeTabView: View {
    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    @Binding var currentChainId: String
    @Environment(\.modelContext) private var modelContext
    @Namespace var namespace
    let transitionID: String = "HomeTabView"
    @State private var isPresented: Bool = false
    @State private var presentDialog: Bool = false
    @State private var isLoading: Bool = false
    @State private var generatedImages: [UIImage]?
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false
    
    @State private var selectedImage: UIImage? = nil
    
    /// Simple memo cache to avoid recompute in hot paths
    @State private var promptCache = [String: [ImagePlaygroundConcept]]()

    
    var body: some View {
        ZStack {
            if let firstImage = selectedImage ?? generatedImages?.first {
                Image(uiImage: firstImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }
            
            VStack {
                Text("HELLO \(currentAccount?.address ?? "")")
                Button("Logout") {
                    try? modelContext.delete(model: NFT.self)
                    try? modelContext.delete(model: EOAccount.self)
                    try? modelContext.delete(model: Tag.self)
                    self.currentAccount = nil
                    currentAddress = ""
                    currentChainId = ""
                }
                Button("refresh UI") {
                    Task { @MainActor in
                        await generateImage()
                    }
                }
                .disabled(isLoading) // Disable refresh button when loading
                
                Button("Show Image Preview") {
                    isPresented = true
                }
                .disabled(generatedImages?.isEmpty != false)
                .padding(.bottom, 8)
            }
            .sheet(isPresented: $isPresented) {
                VStack {
                    if let images = generatedImages {
                        GalleryGrid(images: images) { picked in
                            selectedImage = picked
                            generatedImages = [picked]
                            isPresented = false
                        }
                        .transition(.scale)
                    } else {
                        VStack(spacing: 24) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 60))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                            Text("No images to select")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                }
                .navigationTransition(.zoom(sourceID: transitionID, in: namespace))
            }
            
            // Show placeholder when no images and not loading
            if (generatedImages == nil || generatedImages?.isEmpty == true) && !isLoading {
                ContentUnavailableView("No Images generated yet", systemImage: "photo.on.rectangle.angled")
                    .symbolRenderingMode(.hierarchical)
                    .background(.ultraThinMaterial)
            }
            
            // Overlay loading indicator blocking interaction
            if isLoading {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2)
                    Text("Generating Images...")
                        .foregroundStyle(.white)
                        .font(.headline)
                        .padding(.top, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if generatedImages == nil {
                await generateImage()
            }
        }
        .alert("Error", isPresented: $showErrorAlert, actions: {
            Button("Dismiss", role: .cancel) {
                showErrorAlert = false
            }
        }, message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        })
    }
    
    /// Build a deterministic, personalized Northern Lights prompt.
    /// - Parameters:
    ///   - address: Wallet address; ETH-like will be validated (0x + 40 hex).
    ///   - chainId: Numeric/string chain id; subtly influences motif and intensity.
    ///   - lane: Poster/Photoreal/Synthwave.
    ///   - mood: Optional mood override; falls back to deterministic pick if nil/empty.
    ///   - intensity: 0.0–1.0; if nil, derived deterministically (chain-biased).
    ///   - scene: Prairie/Mountain/Lake silhouettes.
    ///   - snowyForeground: Adds snow/treeline cues when true.
    ///   - locationHint: Human hint (e.g., "Alberta night sky") to bias geography.
    ///
    /// - Returns: Array of ImagePlaygroundConcept.text atoms.
    @discardableResult
    public func themedPrompt(
        address: String,
        chainId: String,
        lane: AuroraLane = .photoreal,
        mood: String? = nil,
        intensity: Double? = nil,
        scene: AuroraScene = .prairie,
        snowyForeground: Bool = false,
        locationHint: String = "Alberta night sky"
    ) -> [ImagePlaygroundConcept] {

        // Normalize inputs
        let addr = address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let chain = chainId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let hasValidAddr = isValidEthAddress(addr)

        // Cache key (parameters included)
        let key = "\(addr)|\(chain)|\(lane.rawValue)|\(mood ?? "-")|\(intensity?.description ?? "-")|\(scene.rawValue)|\(snowyForeground)|\(locationHint)"
        if let cached = promptCache[key] { return cached }

        // Seed from address|chain (cryptographic, deterministic)
        let bytes = seedBytes(addr + "|" + chain)

        // Deterministic pick helper
        @inline(__always)
        func pick<T>(_ arr: [T], _ b: Int) -> T { arr[Int(bytes[b]) % arr.count] }

        // Mood (explicit or seeded)
        let moodAtom = (mood?.isEmpty == false ? mood! : pick(AuroraConfig.moods, 5))

        // Chain motif + chain-biased intensity
        let motif = AuroraConfig.chainThemes[chain] ?? "natural light physics emphasis"
        let chainBias: Double = ["1","mainnet","ethereum","10","42161","8453","137"].contains(chain) ? 0.15 : 0.0
        let seededIntensity = Double(bytes[9]) / 255.0
        let kpi = clamped((intensity ?? seededIntensity) + chainBias, 0, 1)

        // Composition, vibe, scene & optional snow
        let comp = pick(AuroraConfig.compositions, 3)
        let vibe = pick(AuroraConfig.vibes, 11)
        let sceneAtom: String = {
            switch scene {
            case .prairie:  return "broad prairie horizon silhouette"
            case .mountain: return "Rocky Mountains silhouette"
            case .lake:     return "still lake reflection foreground"
            }
        }()
        let snowAtom = snowyForeground ? "snowy foreground, frosted treeline silhouettes" : nil

        // Advanced address-driven pattern (use first 12 hex of address body)
        let addrBody = hasValidAddr ? String(addr.dropFirst(2)) : ""         // strip "0x"
        let addrSeg  = String(addrBody.prefix(12))
        let segBytes = seedBytes(addrSeg)
        let waveFreq = 0.5 + Double(segBytes[0] % 100) / 100.0               // 0.50–1.49
        let filament = ["fine filaments","broad curtains","braided strands","diffuse veil"][Int(segBytes[1]) % 4]
        let patternAtom = hasValidAddr ? "address-encoded \(filament), wave frequency \(String(format: "%.2f", waveFreq))" : "subtle star patterns"

        // Lane atoms
        let laneAtoms: [String] = {
            switch lane {
            case .poster:
                return ["minimalist poster","bold negative space","silkscreen texture"]
            case .synthwave:
                return ["neon glow","retro-futuristic gradient","high contrast","soft grain"]
            case .photoreal:
                return ["long-exposure look","photoreal night landscape","physically plausible light scattering"]
            }
        }()

        // Intensity description
        let intensityAtom: String = {
            switch kpi {
            case 0..<0.33:   return "gentle, calm aurora activity"
            case 0.33..<0.66:return "moderate dancing light curtains"
            default:         return "dramatic high-activity aurora with vivid gradients"
            }
        }()

        // Palette (deterministic HEX colors from seed)
        let paletteAtom = deriveDeterministicPaletteAtom(bytes: bytes)

        // Secondary deterministic variant to avoid sameness
        let variants = ["wide panoramic framing","mid-altitude perspective","grounded horizon with silhouettes"]
        let variant = variants[Int(bytes[27]) % variants.count]

        // Assemble atoms
        var atoms: [String] = [
            "northern lights (\(comp))", "aurora borealis",
            paletteAtom, motif, vibe, sceneAtom, intensityAtom, "mood \(moodAtom)",
            locationHint,
            "ultra-wide 16:9", variant, "starfield detail", "high dynamic range glow"
        ]
        atoms.append(contentsOf: laneAtoms)
        if let snowAtom { atoms.append(snowAtom) }
        atoms.append(contentsOf: AuroraConfig.negatives)

        if hasValidAddr {
            let short = String(addrBody.prefix(6))
            atoms.append("personal signature encoded from \(short) (no visible text)")
            atoms.append(patternAtom)
        }
        if !chain.isEmpty {
            atoms.append("digital asset chain \(chain) (metadata only)")
        }

        let concepts = atoms.map { ImagePlaygroundConcept.text($0) }
        promptCache[key] = concepts
        return concepts
    }
    
    func generateImage() async {
        // Start loading and clear previous images
        isLoading = true
        defer { isLoading = false }
        generatedImages = nil
        
        // Use the themedPrompt function to generate stylized prompt(s)
        let prompts = themedPrompt(address: currentAddress, chainId: currentChainId, lane: .photoreal, scene: .mountain, snowyForeground: false)
        
        do {
            let imageCreator = try await ImageCreator()
            
            let images = imageCreator.images(
                for: prompts,
                style: .illustration,
                limit: 3)
            
            for try await image in images {
                if let generatedImages = self.generatedImages {
                    self.generatedImages = generatedImages + [UIImage(cgImage: image.cgImage)]
                }
                else {
                    self.generatedImages = [UIImage(cgImage: image.cgImage)]
                }
            }
        }
        catch ImageCreator.Error.notSupported {
            errorMessage = "Image creation is not supported on this device."
            showErrorAlert = true
            return
        }
        catch {
            errorMessage = "Failed to generate images. Please try again.\n\(error.localizedDescription)"
            showErrorAlert = true
            return
        }
    }
}


import Foundation
import CryptoKit
import CoreGraphics


/// Public knobs for style and scenery
public enum AuroraLane: String { case poster, photoreal, synthwave }
public enum AuroraScene: String { case prairie, mountain, lake }

/// Centralized configuration for descriptors and themes
private struct AuroraConfig {
    static let compositions = [
        "rayed arcs","curtain","banded horizon","corona overhead","diffuse veil","multi-band ripples"
    ]
    static let vibes = [
        "crisp winter air","moonless sky","polar night clarity","gentle haze","ice-blue starlight"
    ]
    static let moods = [
        "calm","mystical","dramatic","serene","electric"
    ]
    static let negatives = [
        "no text","no watermark","no people","no buildings","no city lights",
        "no extra moons","no cloudy overcast blocking aurora core"
    ]
    /// Tasteful chain motifs (no logos, no on-canvas text)
    static let chainThemes: [String:String] = [
        "1"    : "diamond-facet shimmer, prismatic refractions",
        "mainnet":"diamond-facet shimmer, prismatic refractions",
        "ethereum":"diamond-facet shimmer, prismatic refractions",
        "10"   : "silky fast filaments, forward motion hints",
        "8453" : "clean minimal gradients, architectural calm",
        "42161": "layered ribbons, braided strands",
        "137"  : "soft geometric tessellations in light"
    ]
}





// MARK: - Utilities

@inline(__always)
private func clamped<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { max(lo, min(hi, v)) }

/// SHA-256 → byte array
@inline(__always)
private func seedBytes(_ s: String) -> [UInt8] {
    let h = SHA256.hash(data: Data(s.utf8))
    return Array(h)
}

/// Basic ETH address validator: "0x" + 40 hex chars (case-insensitive)
@inline(__always)
private func isValidEthAddress(_ s: String) -> Bool {
    let t = s.lowercased()
    guard t.hasPrefix("0x"), t.count == 42 else { return false }
    for ch in t.dropFirst(2) {
        let isHex = ("0"..."9").contains(ch) || ("a"..."f").contains(ch)
        if !isHex { return false }
    }
    return true
}

/// Deterministic HEX palette from seed bytes (HSL → HEX for aurora-friendly hues)
private func deriveDeterministicPaletteAtom(bytes: [UInt8]) -> String {
    // Two complementary hues with lively saturation & mid-high lightness
    let h1 = CGFloat(bytes[0]) / 255.0
    let h2 = CGFloat(bytes[7]) / 255.0
    let s1 = 0.60 + 0.30 * CGFloat(bytes[13] % 100) / 100.0
    let s2 = 0.55 + 0.35 * CGFloat(bytes[19] % 100) / 100.0
    let c1 = hslToHex(h: h1, s: s1, l: 0.62)
    let c2 = hslToHex(h: h2, s: s2, l: 0.72)
    return "aurora palette \(c1), \(c2)"
}

/// Minimal HSL→HEX without external deps
private func hslToHex(h: CGFloat, s: CGFloat, l: CGFloat) -> String {
    let c = (1 - abs(2*l - 1)) * s
    let hp = h * 6
    let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
    let (r1,g1,b1): (CGFloat,CGFloat,CGFloat) = {
        switch hp {
        case 0..<1: return (c,x,0)
        case 1..<2: return (x,c,0)
        case 2..<3: return (0,c,x)
        case 3..<4: return (0,x,c)
        case 4..<5: return (x,0,c)
        default:    return (c,0,x)
        }
    }()
    let m = l - c/2
    let r = max(0, min(1, r1 + m))
    let g = max(0, min(1, g1 + m))
    let b = max(0, min(1, b1 + m))
    return String(format:"#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
}


/// New GalleryGrid View added as requested
struct GalleryGrid: View {
    let images: [UIImage]
    let onPick: (UIImage) -> Void
    var body: some View {
        if images.isEmpty {
            VStack(spacing: 24) {
                Image(systemName: "photo.on.rectangle")
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
