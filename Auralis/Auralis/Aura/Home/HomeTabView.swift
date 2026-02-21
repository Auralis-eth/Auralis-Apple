import SwiftUI
import SwiftData
import ImagePlayground

struct HomeTabView: View {
    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    @Binding var currentChainId: String
    @Binding var selectedTab: AppTab
    @Environment(\.modelContext) private var modelContext
    @Namespace var namespace
    let transitionID: String = "HomeTabView"
    
    // MARK: - Background image state
    @State private var isPresented: Bool = false
    @State private var presentDialog: Bool = false
    @State private var isLoading: Bool = false
    @State private var generatedImages: [UIImage]?
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false
    @State private var selectedImage: UIImage? = nil
    @State private var scene: AuroraScene = .mountain

    
    /// Simple memo cache to avoid recompute in hot paths
    @State private var promptCache = [String: [ImagePlaygroundConcept]]()
    
    // MARK: - Avatar image state & cache
    @State private var avatarImage: UIImage? = nil
    
    var body: some View {
        VStack {
            VStack(spacing: 12) {
                ProfileCardView(
                    currentAccount: $currentAccount,
                    currentAddress: $currentAddress,
                    avatarImage: $avatarImage
                )
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .glassEffect(.clear.tint(.surface), in: .rect(cornerRadius: 25, style: .continuous))
                EnergyCardView(time: Date())
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .glassEffect(.clear.tint(.surface), in: .rect(cornerRadius: 25, style: .continuous))
                MusicTileView()
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .glassEffect(.clear.tint(.surface), in: .rect(cornerRadius: 25, style: .continuous))
                FinanceTileView()
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    .glassEffect(.clear.tint(.surface), in: .rect(cornerRadius: 25, style: .continuous))
                
                Button("Open News Feed") {
                    selectedTab = .news
                }

            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                // Background image or avatar image overlay:
                if let firstImage = selectedImage ?? generatedImages?.first {
                    Image(uiImage: firstImage)
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                } else {
                    GatewayBackgroundImage()
                        .ignoresSafeArea()
                }
                Color.background.opacity(0.3)
                    .ignoresSafeArea()
            }

            VStack {
                Button("Logout") {
                    try? modelContext.delete(model: NFT.self)
                    try? modelContext.delete(model: EOAccount.self)
                    try? modelContext.delete(model: Tag.self)
                    self.currentAccount = nil
                    currentAddress = ""
                    currentChainId = ""
                    avatarImage = nil
                    generatedImages = nil
                }
                
                Button("Show Image Preview") {
                    isPresented = true
                }
                .disabled(generatedImages?.isEmpty != false)
                .padding(.bottom, 8)
            }
            .sheet(isPresented: $isPresented) {
                VStack {
                    if let images = generatedImages {
                        GalleryGrid(images: images, selectedScene: $scene) { picked in
                            selectedImage = picked
                            generatedImages = [picked]
                            isPresented = false
                        } onRegenerate: {
                            await generateImage()
                        }
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
            .overlay {
                
                // Overlay loading indicator blocking interaction for background images
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
    }
    
    // MARK: - Background Image Prompt Generation
    
    /// Build a deterministic, personalized Northern Lights prompt.
    /// - Parameters:
    ///   - address: Wallet address; ETH-like will be validated (0x + 40 hex).
    ///   - chainId: Numeric/string chain id; subtly influences motif and intensity.
    ///   - lane: Poster/Photoreal/Synthwave.
    ///   - mood: Optional mood override; falls back to deterministic pick if nil/empty.
    ///   - intensity: 0.0–1.0; if nil, derived deterministically (chain-biased).
    ///   - scene: Prairie/Mountain/Lake silhouettes.
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
        locationHint: String = "Alberta night sky"
    ) -> [ImagePlaygroundConcept] {

        // Normalize inputs
        let addr = address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let chain = chainId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let hasValidAddr = addr.isValidEthAddress()

        // Cache key (parameters included)
        let key = "\(addr)|\(chain)|\(lane.rawValue)|\(mood ?? "-")|\(intensity?.description ?? "-")|\(scene.rawValue)|\(locationHint)"
        if let cached = promptCache[key] { return cached }

        // Seed from address|chain (cryptographic, deterministic)
        let bytes = (addr + "|" + chain).seedBytes

        // Deterministic pick helper
        @inline(__always)
        func pick<T>(_ arr: [T], _ b: Int) -> T { arr[Int(bytes[b]) % arr.count] }

        // Mood (explicit or seeded)
        let moodAtom = (mood?.isEmpty == false ? mood! : pick(AuroraConfig.moods, 5))

        // Chain motif + chain-biased intensity
        let motif = AuroraConfig.chainThemes[chain] ?? "natural light physics emphasis"
        let chainBias: Double = ["1","mainnet","ethereum","10","42161","8453","137"].contains(chain) ? 0.15 : 0.0
        let seededIntensity = Double(bytes[9]) / 255.0
        
        let kpi = max(0, min(1, (intensity ?? seededIntensity) + chainBias))
        
        // Composition, vibe, scene & optional snow
        let comp = pick(AuroraConfig.compositions, 3)
        let sceneAtom: String = {
            switch scene {
            case .prairie:  return "broad prairie horizon silhouette"
            case .mountain: return "Rocky Mountains silhouette"
            case .lake:     return "still lake reflection foreground"
            case .coastline: return "rugged coastline, crashing waves, distant cliffs"
            case .borealForest:
                return "dense boreal forest silhouette, tall spruce and pine"
            case .tundra:
                return "open arctic tundra, low shrubs and permafrost hummocks"
            case .fjord:
                return "steep fjord walls descending to calm water"
            case .glacier:
                return "glacier tongue with fractured crevasses"
            case .iceberg:
                return "drifting icebergs on a cold dark sea"
            case .riverValley:
                return "meandering river valley, soft banks and oxbows"
            case .waterfall:
                return "waterfall plume rising from cliffside"
            case .canyon:
                return "deep canyon walls with layered rock"
            case .badlands:
                return "eroded badlands hoodoos and ridges"
            case .island:
                return "rocky island coastline, sparse wind-bent pines"
            case .highlands:
                return "rolling highlands and moorland"
            case .citySkyline:
                return "distant city skyline lights on the horizon"
            case .ruralFarm:
                return "quiet rural farmstead, barns and open fields"
            case .cabin:
                return "solitary cabin with warm window glow"
            case .lighthouse:
                return "coastal lighthouse perched on a promontory"
            case .observatory:
                return "hilltop observatory dome silhouette"
            case .bridge:
                return "iconic bridge span over dark water"
            case .iceRoad:
                return "frozen ice road stretching across a lake"
            case .polarCamp:
                return "polar expedition camp, low tents and gear"
            case .researchStation:
                return "arctic research station modules and antennae"
            }
        }()

        // Advanced address-driven pattern (use first 12 hex of address body)
        let addrBody = hasValidAddr ? String(addr.dropFirst(2)) : ""         // strip "0x"
        let addrSeg  = String(addrBody.prefix(12))
        let segBytes = addrSeg.seedBytes
        let waveFreq = 0.5 + Double(segBytes[0] % 100) / 100.0               // 0.50–1.49
        let filament = ["fine filaments","broad curtains","braided strands","diffuse veil"][Int(segBytes[1]) % 4]
        let patternAtom = hasValidAddr ? "address-encoded \(filament), wave frequency \(String(format: "%.2f", waveFreq))" : "subtle star patterns"

        // Lane atoms
        let laneAtoms: [String] = {
            switch lane {
            case .poster:
                return [
                    "minimalist poster",
                    "bold negative space",
                    "silkscreen texture",
                ]
            case .synthwave:
                return [
                    "neon glow",
                    "retro-futuristic gradient",
                    "high contrast",
                    "soft grain",
                ]
            case .photoreal:
                return [
                    "long-exposure look",
                    "physically plausible light scattering"
                ]
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

        // Secondary deterministic variant to avoid sameness
        let variants = ["wide panoramic framing","mid-altitude perspective","grounded horizon with silhouettes"]
        let variant = variants[Int(bytes[27]) % variants.count]

        // Assemble atoms
        var atoms: [String] = [
            "northern lights (\(comp))",
            motif,
            sceneAtom,
            intensityAtom,
            "mood \(moodAtom)",
            locationHint,
            variant,
            "high dynamic range glow"
        ]
        atoms.append(contentsOf: laneAtoms)

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
    
    // MARK: - Background Image Generation
    
    func generateImage() async {
        // Start loading and clear previous images
        isLoading = true
        defer { isLoading = false }
        generatedImages = nil
        
        // Use the themedPrompt function to generate stylized prompt(s)
        let prompts = themedPrompt(address: currentAddress, chainId: currentChainId, lane: .poster, scene: scene)
        
        do {
            let imageCreator = try await ImageCreator()
            
            let images = imageCreator.images(
                for: prompts,
                style: .illustration,
                limit: 9)
            
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
            generatedImages = nil
            return
        }
        catch {
            errorMessage = "Failed to generate images. Please try again.\n\(error.localizedDescription)"
            showErrorAlert = true
            return
        }
    }
}

// MARK: - Avatar Style Enum

import Foundation
import CryptoKit
// MARK: - Utilities
extension String {
    /// SHA-256 → byte array
    var seedBytes: [UInt8] {
        let h = SHA256.hash(data: Data(utf8))
        return Array(h)
    }
    
    /// Basic ETH address validator: "0x" + 40 hex chars (case-insensitive)
    func isValidEthAddress() -> Bool {
        let t = lowercased()
        guard t.hasPrefix("0x"), t.count == 42 else { return false }
        for ch in t.dropFirst(2) {
            let isHex = ("0"..."9").contains(ch) || ("a"..."f").contains(ch)
            if !isHex { return false }
        }
        return true
    }
}

struct MusicTileView: View {
    var body: some View {
        VStack {
            SecondaryText("MusicTile")
        }
    }
}

struct FinanceTileView: View {
    var body: some View {
        VStack {
            SecondaryText("FinanceTile")
        }
    }
}

