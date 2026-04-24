import Foundation

struct ProfileAvatarArtworkSupport {
    private let fallbackAvatarAssetNames = (1...7).map { String(format: "testProfile-%02d", $0) }

    func fallbackAvatarAssetName(for address: String) -> String? {
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAddress.isEmpty else {
            return nil
        }

        let imageIndex = Int(normalizedAddress.seedBytes[0]) % fallbackAvatarAssetNames.count
        return fallbackAvatarAssetNames[imageIndex]
    }

    func promptAtoms(address: String, style: AvatarStyle = .abstract) -> [String] {
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let styleAtoms: [String] = {
            switch style {
            case .abstract:
                return ["abstract", "colorful", "modern style"]
            case .character:
                let characterSubjects = [
                    "dog", "cat", "penguin", "robot", "rabbit",
                    "turtle", "wolf", "fox", "deer", "bighorn sheep",
                    "buffalo", "lion", "tiger", "giant panda", "bengal tiger",
                    "african lion", "red kangaroo", "budgerigar", "zebu", "zebra"
                ]
                let seededIndex = Int(normalizedAddress.seedBytes[7]) % characterSubjects.count
                return ["vibrant colors", characterSubjects[seededIndex]]
            case .geometric:
                return ["geometric shapes", "symmetry", "vivid palette"]
            }
        }()

        let moods = ["friendly", "mysterious", "energetic", "calm", "bold"]

        @inline(__always)
        func pick<T>(_ candidates: [T], _ byteIndex: Int) -> T {
            candidates[Int(normalizedAddress.seedBytes[byteIndex]) % candidates.count]
        }

        var atoms: [String] = [
            "digital art",
            "high detail",
            "vibrant colors",
            "clean background",
            "sharp focus",
            "vector style"
        ]
        atoms.append(contentsOf: styleAtoms)
        atoms.append("mood \(pick(moods, 5))")
        return atoms
    }
}

struct HomeAuroraArtworkSupport {
    func promptAtoms(
        address: String,
        chainId: String,
        lane: AuroraLane = .photoreal,
        mood: String? = nil,
        intensity: Double? = nil,
        scene: AuroraScene = .prairie,
        locationHint: String = "Alberta night sky"
    ) -> [String] {
        let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedChain = chainId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasValidAddress = normalizedAddress.isValidEthAddress()
        let bytes = (normalizedAddress + "|" + normalizedChain).seedBytes

        @inline(__always)
        func pick<T>(_ candidates: [T], _ byteIndex: Int) -> T {
            candidates[Int(bytes[byteIndex]) % candidates.count]
        }

        let moodAtom = (mood?.isEmpty == false ? mood : nil) ?? pick(AuroraConfig.moods, 5)
        let motif = AuroraConfig.chainThemes[normalizedChain] ?? "natural light physics emphasis"
        let chainBias: Double = ["1", "mainnet", "ethereum", "10", "42161", "8453", "137"].contains(normalizedChain) ? 0.15 : 0.0
        let seededIntensity = Double(bytes[9]) / 255.0
        let intensityScore = max(0, min(1, (intensity ?? seededIntensity) + chainBias))
        let composition = pick(AuroraConfig.compositions, 3)
        let sceneAtom: String = {
            switch scene {
            case .prairie: return "broad prairie horizon silhouette"
            case .mountain: return "Rocky Mountains silhouette"
            case .lake: return "still lake reflection foreground"
            case .coastline: return "rugged coastline, crashing waves, distant cliffs"
            case .borealForest: return "dense boreal forest silhouette, tall spruce and pine"
            case .tundra: return "open arctic tundra, low shrubs and permafrost hummocks"
            case .fjord: return "steep fjord walls descending to calm water"
            case .glacier: return "glacier tongue with fractured crevasses"
            case .iceberg: return "drifting icebergs on a cold dark sea"
            case .riverValley: return "meandering river valley, soft banks and oxbows"
            case .waterfall: return "waterfall plume rising from cliffside"
            case .canyon: return "deep canyon walls with layered rock"
            case .badlands: return "eroded badlands hoodoos and ridges"
            case .island: return "rocky island coastline, sparse wind-bent pines"
            case .highlands: return "rolling highlands and moorland"
            case .citySkyline: return "distant city skyline lights on the horizon"
            case .ruralFarm: return "quiet rural farmstead, barns and open fields"
            case .cabin: return "solitary cabin with warm window glow"
            case .lighthouse: return "coastal lighthouse perched on a promontory"
            case .observatory: return "hilltop observatory dome silhouette"
            case .bridge: return "iconic bridge span over dark water"
            case .iceRoad: return "frozen ice road stretching across a lake"
            case .polarCamp: return "polar expedition camp, low tents and gear"
            case .researchStation: return "arctic research station modules and antennae"
            }
        }()

        let addressBody = hasValidAddress ? String(normalizedAddress.dropFirst(2)) : ""
        let addressSegment = String(addressBody.prefix(12))
        let segmentBytes = addressSegment.seedBytes
        let waveFrequency = 0.5 + Double(segmentBytes[0] % 100) / 100.0
        let filament = ["fine filaments", "broad curtains", "braided strands", "diffuse veil"][Int(segmentBytes[1]) % 4]
        let patternAtom = hasValidAddress
            ? "address-encoded \(filament), wave frequency \(String(format: "%.2f", waveFrequency))"
            : "subtle star patterns"

        let laneAtoms: [String] = {
            switch lane {
            case .poster:
                return ["minimalist poster", "bold negative space", "silkscreen texture"]
            case .synthwave:
                return ["neon glow", "retro-futuristic gradient", "high contrast", "soft grain"]
            case .photoreal:
                return ["long-exposure look", "physically plausible light scattering"]
            }
        }()

        let intensityAtom: String = {
            switch intensityScore {
            case 0..<0.33:
                return "gentle, calm aurora activity"
            case 0.33..<0.66:
                return "moderate dancing light curtains"
            default:
                return "dramatic high-activity aurora with vivid gradients"
            }
        }()

        let variants = ["wide panoramic framing", "mid-altitude perspective", "grounded horizon with silhouettes"]
        let variant = variants[Int(bytes[27]) % variants.count]

        var atoms: [String] = [
            "northern lights (\(composition))",
            motif,
            sceneAtom,
            intensityAtom,
            "mood \(moodAtom)",
            locationHint,
            variant,
            "high dynamic range glow"
        ]
        atoms.append(contentsOf: laneAtoms)

        if hasValidAddress {
            let shortAddress = String(addressBody.prefix(6))
            atoms.append("personal signature encoded from \(shortAddress) (no visible text)")
        }

        atoms.append(patternAtom)

        if !normalizedChain.isEmpty {
            atoms.append("digital asset chain \(normalizedChain) (metadata only)")
        }

        return atoms
    }
}

struct ProfileENSDisplayResolver {
    func resolveName(for address: String, using ensResolver: any ENSResolving) async -> String? {
        guard !address.isEmpty else {
            return nil
        }

        if let cached = await ensResolver.cachedReverseResolution(forAddress: address),
           cached.isForwardVerified,
           !cached.isStale {
            return cached.ensName
        }

        if let resolved = await ensResolver.reverseLookup(address: address, correlationID: nil),
           resolved.isForwardVerified {
            return resolved.ensName
        }

        return nil
    }
}
