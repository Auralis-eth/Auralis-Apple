import AuralisTestSupport
import Foundation
import Testing

@Suite(.tags(.architecture, .slow))
struct ArchitectureBoundaryTests {
    @Test("app target direct package imports are declared explicitly in Xcode")
    func appDirectPackageImportsAreDeclaredExplicitly() throws {
        let projectRoot = try projectRootURL()
        let declaredProducts = try appTargetPackageProductNames(projectRoot: projectRoot)
        let declaredImportModules = declaredProducts.union(modulesExposedByDeclaredProducts(declaredProducts))
        let knownPackageProducts = try knownPackageProductNames(projectRoot: projectRoot)
        let directPackageImports = try appDirectImports(projectRoot: projectRoot)
            .intersection(knownPackageProducts)
        let undeclaredImports = directPackageImports.subtracting(declaredImportModules)

        #expect(
            undeclaredImports.isEmpty,
            "Direct app package imports must be explicit app target package dependencies: \(undeclaredImports.sorted())"
        )
    }

    @Test("NFTKit production depends on ReceiptsCore and keeps ReceiptStorage test-only")
    func nftKitKeepsReceiptStorageTestOnly() throws {
        let projectRoot = try projectRootURL()
        let packageFile = projectRoot
            .appending(path: "NFTKit")
            .appending(path: "Package.swift")
        let packageText = try String(contentsOf: packageFile, encoding: .utf8)
        let sourceImports = try swiftImports(
            under: projectRoot
                .appending(path: "NFTKit")
                .appending(path: "Sources")
        )

        #expect(packageText.contains("../ReceiptsCore"))
        #expect(packageText.contains("../ReceiptStorage"))
        #expect(sourceImports.contains("ReceiptsCore"))
        #expect(sourceImports.contains("ReceiptStorage") == false)
    }

    @Test("NFTKit layers keep one-way dependencies")
    func nftKitLayerBoundariesStayExplicit() throws {
        let projectRoot = try projectRootURL()
        let nftKitRoot = projectRoot.appending(path: "NFTKit")
        let packageText = try String(
            contentsOf: nftKitRoot.appending(path: "Package.swift"),
            encoding: .utf8
        )
        let facadeExports = try String(
            contentsOf: nftKitRoot
                .appending(path: "Sources")
                .appending(path: "NFTKit")
                .appending(path: "Support")
                .appending(path: "NFTKitPackageExports.swift"),
            encoding: .utf8
        )

        let domainImports = try swiftImports(under: nftKitRoot.appending(path: "Sources/NFTDomain"))
        let providerImports = try swiftImports(under: nftKitRoot.appending(path: "Sources/NFTProviderAdapters"))
        let persistenceImports = try swiftImports(under: nftKitRoot.appending(path: "Sources/NFTPersistence"))

        let forbiddenDomainImports: Set<String> = [
            "AuralisPrimaryPersistence",
            "SwiftUI",
            "SwiftData",
            "ProviderKit",
            "ChainProviders",
            "ExplorerAdapter",
            "ReceiptsCore",
            "NFTProviderAdapters",
            "NFTPersistence",
            "NFTPresentation"
        ]
        let forbiddenProviderImports: Set<String> = [
            "AuralisPrimaryPersistence",
            "SwiftUI",
            "SwiftData",
            "NFTPersistence",
            "NFTPresentation",
            "ReceiptsCore"
        ]
        let forbiddenPersistenceImports: Set<String> = [
            "NFTProviderAdapters",
            "ProviderKit",
            "ChainProviders",
            "ExplorerAdapter",
            "SwiftUI"
        ]
        let forbiddenFacadeExports = [
            "@_exported import ProviderKit",
            "@_exported import ChainProviders",
            "@_exported import ExplorerAdapter"
        ]

        #expect(
            domainImports.intersection(forbiddenDomainImports).isEmpty,
            "NFTDomain must stay pure domain: \(domainImports.intersection(forbiddenDomainImports).sorted())"
        )
        #expect(
            providerImports.intersection(forbiddenProviderImports).isEmpty,
            "NFTProviderAdapters must not own persistence models, UI, SwiftData, receipts, or presentation state: \(providerImports.intersection(forbiddenProviderImports).sorted())"
        )
        #expect(
            packageText.contains(
                """
                name: "NFTProviderAdapters",
                            dependencies: [
                                "NFTDomain",
                                .product(name: "AuralisPrimaryPersistence", package: "AuralisPrimaryModels"),
                """
            ) == false,
            "NFTProviderAdapters must not directly depend on the SwiftData persistence product"
        )
        #expect(
            persistenceImports.intersection(forbiddenPersistenceImports).isEmpty,
            "NFTPersistence must not depend on provider adapters, provider packages, explorer packages, or UI: \(persistenceImports.intersection(forbiddenPersistenceImports).sorted())"
        )
        #expect(
            packageText.contains(
                """
                name: "NFTPersistence",
                            dependencies: [
                                "NFTDomain",
                                "NFTProviderAdapters",
                """
            ) == false,
            "NFTPersistence must not directly depend on NFTProviderAdapters"
        )
        #expect(persistenceImports.contains("SwiftData"))
        #expect(packageText.contains("name: \"NFTDomain\""))
        #expect(packageText.contains("name: \"NFTProviderAdapters\""))
        #expect(packageText.contains("name: \"NFTPersistence\""))
        #expect(packageText.contains("name: \"NFTPresentation\""))
        #expect(
            forbiddenFacadeExports.allSatisfy { facadeExports.contains($0) == false },
            "NFTKit facade must not re-export provider packages"
        )
    }

    @Test("app and feature callers import NFTKit layers explicitly")
    func callersDoNotUseNFTKitUmbrellaImports() throws {
        let projectRoot = try projectRootURL()
        let roots = [
            projectRoot.appending(path: "Auralis"),
            projectRoot.appending(path: "AuralisTests"),
            projectRoot.appending(path: "NFTLibraryFeature").appending(path: "Sources")
        ]
        var offenders: [String] = []

        for root in roots {
            for fileURL in try swiftSourceFiles(under: root) {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                if importedModules(in: source).contains("NFTKit") {
                    offenders.append(
                        fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: "")
                    )
                }
            }
        }

        #expect(
            offenders.isEmpty,
            "Callers should import NFTDomain/NFTProviderAdapters/NFTPersistence/NFTPresentation explicitly: \(offenders.sorted())"
        )
    }

    @Test("TokenStorage does not depend on NFTKit")
    func tokenStorageDoesNotDependOnNFTKit() throws {
        let projectRoot = try projectRootURL()
        let packageFile = projectRoot
            .appending(path: "TokenStorage")
            .appending(path: "Package.swift")
        let packageText = try String(contentsOf: packageFile, encoding: .utf8)
        let sourceImports = try swiftImports(
            under: projectRoot
                .appending(path: "TokenStorage")
                .appending(path: "Sources")
        )

        #expect(packageText.contains("../NFTKit") == false)
        #expect(sourceImports.contains("NFTKit") == false)
    }

    @Test("AuraPlay receipts live in MusicFeature and playback does not import NFTKit")
    func auraPlayReceiptBoundaryStaysInMusicFeature() throws {
        let projectRoot = try projectRootURL()
        let musicFeaturePackage = projectRoot
            .appending(path: "MusicFeature")
            .appending(path: "Package.swift")
        let packageText = try String(contentsOf: musicFeaturePackage, encoding: .utf8)
        let musicFeatureImports = try swiftImports(
            under: projectRoot
                .appending(path: "MusicFeature")
                .appending(path: "Sources")
        )
        let audioEngineFile = projectRoot
            .appending(path: "Auralis")
            .appending(path: "MusicApp")
            .appending(path: "AI")
            .appending(path: "Audio Engine")
            .appending(path: "AudioEngine.swift")
        let audioEngineSource = try String(contentsOf: audioEngineFile, encoding: .utf8)
        let appReceiptFiles = try swiftSourceFiles(
            under: projectRoot
                .appending(path: "Auralis")
                .appending(path: "MusicApp")
                .appending(path: "AuraPlay")
        )
        .filter { $0.path().contains("/Receipts/") }

        #expect(packageText.contains("../ReceiptsCore"))
        #expect(packageText.contains("../CapabilitiesCore"))
        #expect(musicFeatureImports.contains("ReceiptsCore"))
        #expect(musicFeatureImports.contains("CapabilitiesCore"))
        #expect(audioEngineSource.contains("import NFTKit") == false)
        #expect(
            appReceiptFiles.isEmpty,
            "AuraPlay receipt implementation belongs in MusicFeature, not the app target: \(appReceiptFiles.map(\.path).sorted())"
        )
    }

    @Test("first-party Ethereum address validation uses AuralisPrimaryModels EthereumAddress")
    func firstPartyEthereumAddressValidationUsesPrimaryModel() throws {
        let projectRoot = try projectRootURL()
        let forbiddenPatterns = [
            "^0x[" + "a-fA-F0-9" + "]{40}$",
            "^[" + "a-fA-F0-9" + "]{40}$",
            "^0x[" + "a-f0-9" + "]{40}$",
            "^[" + "a-f0-9" + "]{40}$",
            "^0x[" + "0-9a-fA-F" + "]{40}$"
        ]
        let allowedPathSuffixes: Set<String> = [
            "/web3.swift/web3swift/src/Extensions/String+Numeric.swift"
        ]
        var offenders: [String] = []

        for fileURL in try swiftSourceFiles(under: projectRoot) {
            let path = fileURL.path()
            guard !allowedPathSuffixes.contains(where: { path.hasSuffix($0) }) else {
                continue
            }

            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if forbiddenPatterns.contains(where: { source.contains($0) }) {
                offenders.append(path.replacingOccurrences(of: projectRoot.path() + "/", with: ""))
            }
        }

        #expect(
            offenders.isEmpty,
            "Ethereum address parsing must use AuralisPrimaryModels.EthereumAddress instead of local regexes: \(offenders.sorted())"
        )
    }

    @Test("AppServices delegates feature construction to assemblies")
    func appServicesDelegatesFeatureConstructionToAssemblies() throws {
        let projectRoot = try projectRootURL()
        let appServicesFile = projectRoot
            .appending(path: "Auralis")
            .appending(path: "AppServices.swift")
        let source = try String(contentsOf: appServicesFile, encoding: .utf8)
        let forbiddenConstructionTokens = [
            "NFTService(",
            "AudioEngine(",
            "AuraPlayModelContainer.make",
            "SwiftDataAccountStore(",
            "ReceiptStores.live",
            "SwiftDataTokenHoldingsStore(",
            "LiveERC20HoldingsSyncUseCase(",
            "PrivacyResetServices.live",
            "PolicyActionGateService("
        ]
        let offenders = forbiddenConstructionTokens.filter { source.contains($0) }

        #expect(
            offenders.isEmpty,
            "AppServices.swift should stay a thin composition aggregate; feature construction belongs in assemblies: \(offenders)"
        )
    }

    @Test("assemblies do not keep temporary static live pass-throughs")
    func assembliesDoNotKeepTemporaryStaticLivePassThroughs() throws {
        let projectRoot = try projectRootURL()
        let assembliesRoot = projectRoot
            .appending(path: "Auralis")
            .appending(path: "Assemblies")
        let offenders = try swiftSourceFiles(under: assembliesRoot)
            .filter { fileURL in
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                return source.contains("static func live") || source.contains("static let live")
            }
            .map { $0.path().replacingOccurrences(of: projectRoot.path() + "/", with: "") }

        #expect(
            offenders.isEmpty,
            "Feature assemblies should be injected instance values, not temporary static live pass-throughs: \(offenders.sorted())"
        )
    }

    @Test("shell selection is not persisted with UserDefaults")
    func shellSelectionDoesNotUseUserDefaultsPersistence() throws {
        let projectRoot = try projectRootURL()
        let appSources = projectRoot.appending(path: "Auralis")
        let sourceFiles = try swiftSourceFiles(under: appSources)
        var offenders: [String] = []

        for fileURL in sourceFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains("UserDefaultsShellSelectionPersistence") {
                offenders.append(fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: ""))
            }
        }

        #expect(
            offenders.isEmpty,
            "Shell selection is wallet metadata and must use KeychainShellSelectionPersistence: \(offenders.sorted())"
        )
    }

    @Test("app observable state uses Observation instead of ObservableObject wrappers")
    func appObservableStateUsesObservation() throws {
        let projectRoot = try projectRootURL()
        let appSources = projectRoot.appending(path: "Auralis")
        let forbiddenTokens = [
            "ObservableObject",
            "@Published",
            "@StateObject",
            "@ObservedObject",
            "@EnvironmentObject"
        ]
        var offenders: [String] = []

        for fileURL in try swiftSourceFiles(under: appSources) {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if forbiddenTokens.contains(where: { source.contains($0) }) {
                offenders.append(fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: ""))
            }
        }

        #expect(
            offenders.isEmpty,
            "Use @Observable/@State/@Bindable instead of ObservableObject wrappers in app code: \(offenders.sorted())"
        )
    }

    @Test("feature package source boundaries use intended imports and Observation")
    func featurePackageSourceBoundariesUseIntendedImportsAndObservation() throws {
        let projectRoot = try projectRootURL()
        let rules: [PackageSourceBoundaryRule] = [
            PackageSourceBoundaryRule(
                rootPath: "MusicFeature/Sources/MusicFeature/Domain",
                forbiddenImports: [
                    "AuralisPrimaryPersistence",
                    "AuraUI",
                    "CapabilitiesCore",
                    "ReceiptsCore",
                    "SwiftData",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "MusicFeature domain values must stay portable and UI/storage-free"
            ),
            PackageSourceBoundaryRule(
                rootPath: "MusicFeature/Sources/MusicFeature/Core",
                forbiddenImports: [
                    "AuralisPrimaryPersistence",
                    "AuraUI",
                    "CapabilitiesCore",
                    "ReceiptsCore",
                    "SwiftData",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "MusicFeature core configuration must stay independent of UI, persistence, and receipt services"
            ),
            PackageSourceBoundaryRule(
                rootPath: "MusicFeature/Sources/MusicFeature/Services",
                forbiddenImports: [
                    "AuralisPrimaryPersistence",
                    "AuraUI",
                    "NFTKit",
                    "NFTDomain",
                    "NFTPersistence",
                    "NFTPresentation",
                    "NFTProviderAdapters",
                    "SwiftData",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "MusicFeature service contracts must not depend on UI, SwiftData, or NFT implementation layers"
            ),
            PackageSourceBoundaryRule(
                rootPath: "MusicFeature/Sources/MusicFeature/Persistence",
                forbiddenImports: [
                    "AuraUI",
                    "NFTKit",
                    "NFTDomain",
                    "NFTPersistence",
                    "NFTPresentation",
                    "NFTProviderAdapters",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "MusicFeature persistence may use SwiftData but must not reach into UI or NFT layers"
            ),
            PackageSourceBoundaryRule(
                rootPath: "MusicFeature/Sources/MusicFeature/Receipts",
                forbiddenImports: [
                    "AuralisPrimaryPersistence",
                    "AuraUI",
                    "NFTKit",
                    "NFTDomain",
                    "NFTPersistence",
                    "NFTPresentation",
                    "NFTProviderAdapters",
                    "ReceiptStorage",
                    "SwiftData",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "MusicFeature receipt logic depends on receipt contracts, not app storage, UI, or NFT layers"
            ),
            PackageSourceBoundaryRule(
                rootPath: "MusicFeature/Sources/MusicFeature/Presentation",
                forbiddenImports: [
                    "NFTKit",
                    "NFTProviderAdapters",
                    "ProviderKit",
                    "ReceiptStorage"
                ],
                reason: "MusicFeature presentation may use SwiftUI and SwiftData-facing models but not provider or storage implementation packages"
            ),
            PackageSourceBoundaryRule(
                rootPath: "MusicFeature/Sources/MusicFeature/App",
                forbiddenImports: [
                    "NFTKit",
                    "NFTProviderAdapters",
                    "ProviderKit",
                    "ReceiptStorage"
                ],
                reason: "MusicFeature app entry points may compose presentation but not provider or storage implementation packages"
            ),
            PackageSourceBoundaryRule(
                rootPath: "NFTLibraryFeature/Sources/NFTLibraryFeature/Domain",
                forbiddenImports: [
                    "AuraUI",
                    "ExplorerAdapter",
                    "NFTKit",
                    "NFTDomain",
                    "NFTPersistence",
                    "NFTPresentation",
                    "NFTProviderAdapters",
                    "OperatorCore",
                    "SwiftData",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "NFTLibraryFeature domain routing and sorting must stay free of UI, provider, and concrete NFTKit layers"
            ),
            PackageSourceBoundaryRule(
                rootPath: "NFTLibraryFeature/Sources/NFTLibraryFeature/Services",
                forbiddenImports: [
                    "AuralisPrimaryPersistence",
                    "AuraUI",
                    "ExplorerAdapter",
                    "NFTKit",
                    "NFTDomain",
                    "NFTPersistence",
                    "NFTPresentation",
                    "NFTProviderAdapters",
                    "SwiftData",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "NFTLibraryFeature services must stay domain-facing and avoid UI, persistence, and NFT provider layers"
            ),
            PackageSourceBoundaryRule(
                rootPath: "NFTLibraryFeature/Sources/NFTLibraryFeature/Support",
                forbiddenImports: [
                    "AuraUI",
                    "ExplorerAdapter",
                    "NFTKit",
                    "NFTDomain",
                    "NFTPersistence",
                    "NFTPresentation",
                    "NFTProviderAdapters",
                    "OperatorCore",
                    "SwiftData",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "NFTLibraryFeature support mappers must stay presentation-data oriented without UI or provider dependencies"
            ),
            PackageSourceBoundaryRule(
                rootPath: "NFTLibraryFeature/Sources/NFTLibraryFeature/Presentation",
                forbiddenImports: [
                    "NFTKit",
                    "ProviderKit",
                    "ReceiptStorage"
                ],
                reason: "NFTLibraryFeature presentation may use SwiftUI and explicit NFTKit layer products, but not umbrella/provider/storage implementation imports"
            ),
            PackageSourceBoundaryRule(
                rootPath: "NFTKit/Sources/NFTDomain",
                forbiddenImports: [
                    "AuralisPrimaryPersistence",
                    "ChainProviders",
                    "ExplorerAdapter",
                    "NFTPersistence",
                    "NFTPresentation",
                    "NFTProviderAdapters",
                    "ProviderKit",
                    "ReceiptsCore",
                    "SwiftData",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "NFTDomain must stay pure domain"
            ),
            PackageSourceBoundaryRule(
                rootPath: "NFTKit/Sources/NFTProviderAdapters",
                forbiddenImports: [
                    "AuralisPrimaryPersistence",
                    "NFTPersistence",
                    "NFTPresentation",
                    "ReceiptsCore",
                    "SwiftData",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "NFTProviderAdapters must not own persistence models, UI, SwiftData, receipts, or presentation state"
            ),
            PackageSourceBoundaryRule(
                rootPath: "NFTKit/Sources/NFTPersistence",
                forbiddenImports: [
                    "ChainProviders",
                    "ExplorerAdapter",
                    "NFTProviderAdapters",
                    "ProviderKit",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "NFTPersistence must not depend on provider adapters, provider packages, explorer packages, or UI"
            ),
            PackageSourceBoundaryRule(
                rootPath: "NFTKit/Sources/NFTPresentation",
                forbiddenImports: [
                    "ChainProviders",
                    "ExplorerAdapter",
                    "ProviderKit",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "NFTPresentation may orchestrate NFT layers and SwiftData models, but not UI or provider implementation packages"
            ),
            PackageSourceBoundaryRule(
                rootPath: "NFTKit/Sources/NFTKit",
                forbiddenImports: [
                    "ChainProviders",
                    "ExplorerAdapter",
                    "ProviderKit",
                    "SwiftData",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "NFTKit facade must remain a thin export layer"
            ),
            PackageSourceBoundaryRule(
                rootPath: "AuralisPrimaryModels/Sources/AuralisPrimaryModels",
                forbiddenImports: [
                    "AuralisPrimaryPersistence",
                    "AuraUI",
                    "MusicFeature",
                    "NFTKit",
                    "NFTDomain",
                    "NFTPersistence",
                    "NFTPresentation",
                    "NFTProviderAdapters",
                    "Observation",
                    "SwiftData",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "AuralisPrimaryModels must stay pure portable domain values"
            ),
            PackageSourceBoundaryRule(
                rootPath: "AuralisPrimaryModels/Sources/AuralisPrimaryPersistence",
                forbiddenImports: [
                    "AuraUI",
                    "MusicFeature",
                    "NFTKit",
                    "NFTDomain",
                    "NFTPersistence",
                    "NFTPresentation",
                    "NFTProviderAdapters",
                    "Observation",
                    "ProviderKit",
                    "SwiftUI",
                    "UIKit"
                ],
                reason: "AuralisPrimaryPersistence may use SwiftData but must not import UI, feature, provider, or observation layers"
            )
        ]
        let legacyObservationTokens = [
            "ObservableObject",
            "@Published",
            "@StateObject",
            "@ObservedObject",
            "@EnvironmentObject"
        ]
        var importOffenders: [String] = []
        var observationOffenders: [String] = []

        for rule in rules {
            let sourceRoot = projectRoot.appending(path: rule.rootPath)
            for fileURL in try swiftSourceFiles(under: sourceRoot) {
                let relativePath = fileURL.path()
                    .replacingOccurrences(of: projectRoot.path() + "/", with: "")
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                let forbiddenImports = importedModules(in: source).intersection(rule.forbiddenImports)

                if forbiddenImports.isEmpty == false {
                    importOffenders.append(
                        "\(relativePath) imports \(forbiddenImports.sorted()) - \(rule.reason)"
                    )
                }

                let forbiddenTokens = legacyObservationTokens.filter(source.contains)
                if forbiddenTokens.isEmpty == false {
                    observationOffenders.append(
                        "\(relativePath) uses \(forbiddenTokens.sorted())"
                    )
                }
            }
        }

        #expect(
            importOffenders.isEmpty,
            "Package source imports must match each target's intended layer: \(importOffenders.sorted())"
        )
        #expect(
            observationOffenders.isEmpty,
            "Package SwiftUI/observable sources must use Observation instead of ObservableObject wrappers: \(observationOffenders.sorted())"
        )
    }

    @Test("SwiftUI queries do not own shell selection")
    func swiftUIQueriesDoNotOwnShellSelection() throws {
        let projectRoot = try projectRootURL()
        let scannedRoots = [
            projectRoot.appending(path: "Auralis"),
            projectRoot.appending(path: "MusicFeature/Sources")
        ]
        let allowedFiles: Set<String> = [
            "Auralis/Aura/MainAuraView.swift", // read-only activeAccountID resolver
            "Auralis/Aura/Home/AccountSwitcherSheet.swift" // account-list host plus approved adapters
        ]
        let forbiddenSnippets = [
            ".persistCurrentChain(",
            ".persistPreferredChain(",
            ".selectAccount(",
            ".removeAccount(",
            ".wrappedValue =",
            "selectedAccount =",
            "selectedChain ="
        ]

        var offenders: [String] = []
        for root in scannedRoots {
            for fileURL in try swiftSourceFiles(under: root) {
                let relativePath = fileURL.path()
                    .replacingOccurrences(of: projectRoot.path() + "/", with: "")
                guard !isAllowedPath(relativePath, allowedFiles: allowedFiles) else { continue }

                let source = try String(contentsOf: fileURL, encoding: .utf8)
                guard source.contains("@Query"), source.contains(": View") else { continue }

                if forbiddenSnippets.contains(where: source.contains) {
                    offenders.append(relativePath)
                }
            }
        }

        #expect(
            offenders.isEmpty,
            "SwiftUI @Query views must not own shell selection writes: \(offenders.sorted())"
        )
    }

    @Test("account switcher current chain changes route through shell")
    func accountSwitcherCurrentChainChangesRouteThroughShell() throws {
        let projectRoot = try projectRootURL()
        let accountSwitcherFile = projectRoot
            .appending(path: "AccountsFeature/Sources/AccountsFeature/Presentation/AddressTextField.swift")
        let source = try String(contentsOf: accountSwitcherFile, encoding: .utf8)
        let currentChainCase = try extractSwitchCase(named: "case .current:", from: source)

        #expect(
            currentChainCase.contains(".persistCurrentChain(") == false,
            "AccountSwitcherSheet must not persist active current-chain selection before ShellStore coordinates the shell action"
        )
        #expect(
            source.contains("try await onCurrentChainChange(plan.to, correlationID)"),
            "AccountSwitcherSheet current-chain changes must call the injected shell callback"
        )
    }

    private func appTargetPackageProductNames(projectRoot: URL) throws -> Set<String> {
        let projectFile = projectRoot
            .appending(path: "Auralis.xcodeproj")
            .appending(path: "project.pbxproj")
        let projectText = try String(contentsOf: projectFile, encoding: .utf8)
        let targetBlock = try extractBlock(
            named: "6FB455DA2CC5BEBB009A055C /* Auralis */ =",
            from: projectText
        )
        let dependencyBlock = try extractList(named: "packageProductDependencies", from: targetBlock)
        return Set(commentNames(in: dependencyBlock))
    }

    private func modulesExposedByDeclaredProducts(_ productNames: Set<String>) -> Set<String> {
        var modules = Set<String>()

        if productNames.contains("AuralisPrimaryModels") {
            modules.insert("AuralisPrimaryPersistence")
        }

        return modules
    }

    private func knownPackageProductNames(projectRoot: URL) throws -> Set<String> {
        let packageDirectories = try FileManager.default.contentsOfDirectory(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var productNames = Set<String>()

        for directory in packageDirectories {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            let packageFile = directory.appending(path: "Package.swift")
            guard FileManager.default.fileExists(atPath: packageFile.path()) else { continue }

            let packageText = try String(contentsOf: packageFile, encoding: .utf8)
            productNames.formUnion(libraryProductNames(in: packageText))
        }

        productNames.formUnion(["CodeScanner", "web3.swift"])
        return productNames
    }

    private func appDirectImports(projectRoot: URL) throws -> Set<String> {
        try swiftImports(
            under: projectRoot.appending(path: "Auralis"),
            excludingPathComponents: ["/AuralisTests/", "/AuralisUITests/"]
        )
    }

    private func swiftImports(
        under root: URL,
        excludingPathComponents excludedComponents: [String] = []
    ) throws -> Set<String> {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var imports = Set<String>()

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard !excludedComponents.contains(where: { fileURL.path().contains($0) }) else { continue }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let source = try String(contentsOf: fileURL, encoding: .utf8)
            imports.formUnion(importedModules(in: source))
        }

        return imports
    }

    private func swiftSourceFiles(under root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var files: [URL] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            files.append(fileURL)
        }

        return files
    }

    private func importedModules(in source: String) -> Set<String> {
        var modules = Set<String>()

        for line in source.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") else { continue }

            let importTail = trimmed.dropFirst("import ".count)
            let moduleName = importTail.split(whereSeparator: { $0 == " " || $0 == "." }).first
            if let moduleName {
                modules.insert(String(moduleName))
            }
        }

        return modules
    }

    private func libraryProductNames(in packageText: String) -> Set<String> {
        var productNames = Set<String>()
        let pattern = #"\.library\s*\(\s*name:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(packageText.startIndex..<packageText.endIndex, in: packageText)

        for match in regex.matches(in: packageText, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: packageText) else { continue }
            productNames.insert(String(packageText[nameRange]))
        }

        return productNames
    }

    private func extractBlock(named objectName: String, from text: String) throws -> String {
        guard let nameRange = text.range(of: objectName) else {
            Issue.record("Unable to find project object named \(objectName)")
            throw ArchitectureFixtureError()
        }
        guard let blockStart = text[nameRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("Unable to find block start for \(objectName)")
            throw ArchitectureFixtureError()
        }

        return try balancedSubstring(from: blockStart, open: "{", close: "}", in: text)
    }

    private func extractList(named listName: String, from text: String) throws -> String {
        guard let nameRange = text.range(of: listName) else {
            Issue.record("Unable to find list named \(listName)")
            throw ArchitectureFixtureError()
        }
        guard let listStart = text[nameRange.upperBound...].firstIndex(of: "(") else {
            Issue.record("Unable to find list start for \(listName)")
            throw ArchitectureFixtureError()
        }

        return try balancedSubstring(from: listStart, open: "(", close: ")", in: text)
    }

    private func extractSwitchCase(named caseName: String, from text: String) throws -> String {
        guard let caseRange = text.range(of: caseName) else {
            Issue.record("Unable to find switch case named \(caseName)")
            throw ArchitectureFixtureError()
        }

        let remaining = text[caseRange.lowerBound...]
        if let nextCaseRange = remaining.dropFirst(caseName.count).range(of: "\n                case ") {
            return String(text[caseRange.lowerBound..<nextCaseRange.lowerBound])
        }

        if let switchEndRange = remaining.range(of: "\n                }\n") {
            return String(text[caseRange.lowerBound..<switchEndRange.lowerBound])
        }

        Issue.record("Unable to extract switch case named \(caseName)")
        throw ArchitectureFixtureError()
    }

    private func isAllowedPath(_ path: String, allowedFiles: Set<String>) -> Bool {
        allowedFiles.contains(path) || allowedFiles.contains { path.hasSuffix($0) }
    }

    private struct PackageSourceBoundaryRule {
        let rootPath: String
        let forbiddenImports: Set<String>
        let reason: String
    }

    private func balancedSubstring(
        from start: String.Index,
        open: Character,
        close: Character,
        in text: String
    ) throws -> String {
        var depth = 0
        var current = start

        while current < text.endIndex {
            let character = text[current]
            if character == open {
                depth += 1
            } else if character == close {
                depth -= 1
                if depth == 0 {
                    return String(text[start...current])
                }
            }
            current = text.index(after: current)
        }

        Issue.record("Unable to find balanced substring starting at \(start)")
        throw ArchitectureFixtureError()
    }

    private func commentNames(in text: String) -> [String] {
        var names: [String] = []
        let pattern = #"/\*\s*([^*]+?)\s*\*/"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        for match in regex.matches(in: text, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            names.append(String(text[nameRange]))
        }

        return names
    }

    private func projectRootURL(filePath: String = #filePath) throws -> URL {
        var candidate = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()

        while candidate.path != "/" {
            let projectPath = candidate.appending(path: "Auralis.xcodeproj").path()
            if FileManager.default.fileExists(atPath: projectPath) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        Issue.record("Unable to locate project root from \(filePath)")
        throw ArchitectureFixtureError()
    }
}

private struct ArchitectureFixtureError: Error {}
