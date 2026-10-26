import AuralisTestSupport
import Foundation
import Testing

@Suite(.tags(.architecture, .slow))
struct ArchitectureBoundaryTests {
    @Test("first-party package dependency graph is acyclic and packages are not empty identity stubs")
    func firstPartyPackageGraphIsAcyclicAndConcrete() throws {
        let projectRoot = try projectRootURL()
        let packageDirectories = try FileManager.default.contentsOfDirectory(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            FileManager.default.fileExists(atPath: $0.appending(path: "Package.swift").path())
        }
        let packageNames = Set(packageDirectories.map(\.lastPathComponent))
        var graph: [String: Set<String>] = [:]
        var emptyPackages: [String] = []

        for directory in packageDirectories {
            let packageName = directory.lastPathComponent
            let packageText = try String(
                contentsOf: directory.appending(path: "Package.swift"),
                encoding: .utf8
            )
            graph[packageName] = localPackageDependencies(in: packageText)
                .intersection(packageNames)

            let sources = directory.appending(path: "Sources")
            if try swiftSourceFiles(under: sources).isEmpty {
                emptyPackages.append(packageName)
            }
        }

        let cycles = dependencyCycles(in: graph)
        #expect(
            cycles.isEmpty,
            "First-party SPM dependencies must remain acyclic: \(cycles.sorted())"
        )
        #expect(
            emptyPackages.isEmpty,
            "Identity packages must contain real production source instead of acting as empty dependency aliases: \(emptyPackages.sorted())"
        )
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "AgentIdentityCore/Package.swift").path()
            ) == false,
            "AgentIdentityCore was retired; identity must remain owned by RuntimeCore instead of returning as a stub package."
        )

        let engineManifest = try String(
            contentsOf: projectRoot.appending(path: "AuraPlayEngines/Package.swift"),
            encoding: .utf8
        )
        for target in ["AuraPlayMediaCore", "AuraPlayAudioEngine", "AuraPlayVideoEngine"] {
            #expect(engineManifest.contains("name: \"\(target)\""))
            #expect(
                FileManager.default.fileExists(
                    atPath: projectRoot.appending(path: "\(target)/Package.swift").path()
                ) == false,
                "\(target) must remain an internal AuraPlayEngines target, not return as a package root."
            )
        }

        let foundationManifest = try String(
            contentsOf: projectRoot.appending(path: "AuralisFoundation/Package.swift"),
            encoding: .utf8
        )
        for target in ["CapabilitiesCore", "SwiftDataAdapters", "UserDefaultsAdapters"] {
            #expect(foundationManifest.contains("name: \"\(target)\""))
            #expect(
                FileManager.default.fileExists(
                    atPath: projectRoot.appending(path: "\(target)/Package.swift").path()
                ) == false,
                "\(target) must remain an internal AuralisFoundation target, not return as a package root."
            )
        }

        let runtimeManifest = try String(
            contentsOf: projectRoot.appending(path: "RuntimeCore/Package.swift"),
            encoding: .utf8
        )
        for target in [
            "PlannerCore", "PlaybookCore", "PerformanceCore", "EvalCore", "SchedulingCore"
        ] {
            #expect(runtimeManifest.contains("name: \"\(target)\""))
            #expect(
                FileManager.default.fileExists(
                    atPath: projectRoot.appending(path: "\(target)/Package.swift").path()
                ) == false,
                "\(target) must remain an internal AuralisRuntime target, not return as a package root."
            )
        }

        let runtimeKitManifest = try String(
            contentsOf: projectRoot.appending(path: "RuntimeKit/Package.swift"),
            encoding: .utf8
        )
        #expect(runtimeKitManifest.contains("name: \"OperatorRuntimeStorage\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "OperatorRuntimeStorage/Package.swift").path()
            ) == false,
            "OperatorRuntimeStorage must remain an internal AuralisAppShell target."
        )

        let appShellManifest = try String(
            contentsOf: projectRoot.appending(path: "RuntimeKit/Package.swift"),
            encoding: .utf8
        )
        #expect(appShellManifest.contains("name: \"AuralisShellCore\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "AuralisShellCore/Package.swift").path()
            ) == false,
            "AuralisShellCore must remain an internal AuralisAppShell target, not return as a package root."
        )

        let operatorsManifest = try String(
            contentsOf: projectRoot.appending(path: "OperatorsFeature/Package.swift"),
            encoding: .utf8
        )
        #expect(operatorsManifest.contains("name: \"SocialCore\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "SocialCore/Package.swift").path()
            ) == false,
            "SocialCore must remain an internal AuralisOperators target, not return as a package root."
        )
        #expect(operatorsManifest.contains("name: \"OperatorCore\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "OperatorCore/Package.swift").path()
            ) == false,
            "OperatorCore must remain an internal AuralisOperators target, not return as a package root."
        )
        #expect(operatorsManifest.contains("name: \"NFTLibraryFeature\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "NFTLibraryFeature/Package.swift").path()
            ) == false,
            "NFTLibraryFeature must remain an internal AuralisOperators target, not return as a package root."
        )
        #expect(operatorsManifest.contains("name: \"MusicFeature\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "MusicFeature/Package.swift").path()
            ) == false,
            "MusicFeature must remain an internal AuralisOperators target, not return as a package root."
        )

        let missionControlManifest = try String(
            contentsOf: projectRoot.appending(path: "MissionControlFeature/Package.swift"),
            encoding: .utf8
        )
        #expect(missionControlManifest.contains("name: \"TrustedUIKit\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "TrustedUIKit/Package.swift").path()
            ) == false,
            "TrustedUIKit must remain an internal MissionControl target, not return as a package root."
        )

        let policyManifest = try String(
            contentsOf: projectRoot.appending(path: "PolicyCore/Package.swift"),
            encoding: .utf8
        )
        #expect(policyManifest.contains("name: \"AutopilotCore\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "AutopilotCore/Package.swift").path()
            ) == false,
            "AutopilotCore must remain an internal AuralisPolicy target, not return as a package root."
        )

        let providerManifest = try String(
            contentsOf: projectRoot.appending(path: "AccountsCore/Package.swift"),
            encoding: .utf8
        )
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "ProviderKit/Package.swift").path()
            ) == false,
            "ProviderKit must remain an internal AuralisCrypto target."
        )
        #expect(providerManifest.contains("name: \"ChainProviders\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "ChainProviders/Package.swift").path()
            ) == false,
            "ChainProviders must remain an internal AuralisCrypto target, not return as a package root."
        )
        #expect(providerManifest.contains("name: \"ExplorerAdapter\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "ExplorerAdapter/Package.swift").path()
            ) == false,
            "ExplorerAdapter must remain an internal AuralisCrypto target, not return as a package root."
        )
        #expect(providerManifest.contains("name: \"ENS\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "ENS/Package.swift").path()
            ) == false,
            "ENS must remain an internal AuralisCrypto target, not return as a package root."
        )
        for target in ["NFTKit", "NFTDomain", "NFTProviderAdapters", "NFTPersistence", "NFTPresentation"] {
            #expect(providerManifest.contains("name: \"\(target)\""))
        }
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "NFTKit/Package.swift").path()
            ) == false,
            "NFTKit must remain an internal AuralisCrypto target."
        )

        let walletAccountsManifest = try String(
            contentsOf: projectRoot.appending(path: "AccountsCore/Package.swift"),
            encoding: .utf8
        )
        for target in [
            "WalletConnectorKit",
            "WalletConnectorKitReownAdapter",
            "WalletConnectorKitCoinbaseAdapter",
            "WalletConnectorKitMetaMaskAdapter",
            "WalletConnectorKitPrivyAdapter",
            "WalletConnectorKitDynamicAdapter",
            "WalletConnectorKitSolanaAdapter"
        ] {
            #expect(walletAccountsManifest.contains("name: \"\(target)\""))
        }
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "WalletConnectorKit/Package.swift").path()
            ) == false,
            "WalletConnectorKit adapters must remain internal AuralisCrypto targets."
        )

        let accountsManifest = try String(
            contentsOf: projectRoot.appending(path: "AccountsCore/Package.swift"),
            encoding: .utf8
        )
        #expect(accountsManifest.contains("name: \"AccountStorage\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "AccountStorage/Package.swift").path()
            ) == false,
            "AccountStorage must remain an internal AuralisCrypto target, not return as a package root."
        )
        #expect(accountsManifest.contains("name: \"TokenStorage\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "TokenStorage/Package.swift").path()
            ) == false,
            "TokenStorage must remain an internal AuralisCrypto target, not return as a package root."
        )
        #expect(accountsManifest.contains("name: \"AccountsFeature\""))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(path: "AccountsFeature/Package.swift").path()
            ) == false,
            "AccountsFeature must remain an internal AuralisCrypto target, not return as a package root."
        )

        let receiptsManifest = try String(
            contentsOf: projectRoot.appending(path: "ReceiptsCore/Package.swift"),
            encoding: .utf8
        )
        for target in ["ArtifactCore", "ArtifactStorage", "ReceiptStorage"] {
            #expect(receiptsManifest.contains("name: \"\(target)\""))
            #expect(
                FileManager.default.fileExists(
                    atPath: projectRoot.appending(path: "\(target)/Package.swift").path()
                ) == false,
                "\(target) must remain an internal AuralisReceipts target, not return as a package root."
            )
        }

        let tokenNativePresentation = try String(
            contentsOf: projectRoot.appending(
                path: "AccountsCore/Sources/TokenStorage/Chain+NativeToken.swift"
            ),
            encoding: .utf8
        )
        let tokenFreshnessPolicy = try String(
            contentsOf: projectRoot.appending(
                path: "AccountsCore/Sources/TokenStorage/TokenHoldingsMetadataFreshnessPolicy.swift"
            ),
            encoding: .utf8
        )
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(
                    path: "AuralisPrimaryModels/Sources/AuralisPrimaryModels/TokenHoldingSupport.swift"
                ).path()
            ) == false
        )
        #expect(tokenNativePresentation.contains("var nativeTokenSymbol"))
        #expect(tokenNativePresentation.contains("var nativeTokenDisplayName"))
        #expect(tokenFreshnessPolicy.contains("public enum TokenHoldingsMetadataFreshnessPolicy"))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(
                    path: "AuralisPrimaryModels/Sources/AuralisPrimaryModels/PrimaryStoreCopy.swift"
                ).path()
            ) == false,
            "App-launch recovery copy belongs to AppShell composition, not shared domain models."
        )
        let foundationJSONValue = try String(
            contentsOf: projectRoot.appending(
                path: "AuralisFoundation/Sources/AuralisFoundation/JSONValue.swift"
            ),
            encoding: .utf8
        )
        let musicAlchemyClient = try String(
            contentsOf: projectRoot.appending(
                path: "OperatorsFeature/Sources/MusicFeature/Discovery/AlchemyNFTClient.swift"
            ),
            encoding: .utf8
        )
        #expect(foundationJSONValue.contains("public enum JSONValue"))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(
                    path: "AuralisPrimaryModels/Sources/AuralisPrimaryModels/JSONValue.swift"
                ).path()
            ) == false
        )
        #expect(musicAlchemyClient.contains("private enum JSONValue") == false)

        let accountSummary = try String(
            contentsOf: projectRoot.appending(
                path: "AccountsCore/Sources/AccountsCore/Models/AccountSummary.swift"
            ),
            encoding: .utf8
        )
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(
                    path: "AuralisPrimaryModels/Sources/AuralisPrimaryModels/PortableDomainValues.swift"
                ).path()
            ) == false
        )
        for unusedType in [
            "NFTIdentity",
            "NFTMetadataSnapshot",
            "TokenHoldingDescriptor",
            "PlaylistDescriptor",
            "SearchHistoryValue",
        ] {
            #expect(
                accountSummary.contains("struct \(unusedType)") == false,
                "Do not restore speculative portable models without a real domain consumer: \(unusedType)"
            )
        }
        #expect(accountSummary.contains("public struct AccountSummary"))
        let musicURLSupport = try String(
            contentsOf: projectRoot.appending(
                path: "OperatorsFeature/Sources/MusicFeature/Persistence/NFT+MusicURL.swift"
            ),
            encoding: .utf8
        )
        #expect(musicURLSupport.contains("public extension NFT"))
        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(
                    path: "AuralisPrimaryModels/Sources/AuralisPrimaryModels/MediaURLSupport.swift"
                ).path()
            ) == false
        )

        let accountStorage = try String(
            contentsOf: projectRoot.appending(
                path: "AccountsCore/Sources/AccountStorage/SwiftDataAccountStore.swift"
            ),
            encoding: .utf8
        )
        let scopedParticipant = try String(
            contentsOf: projectRoot.appending(
                path: "AuralisFoundation/Sources/SwiftDataAdapters/ScopedPersistenceParticipant.swift"
            ),
            encoding: .utf8
        )
        let tokenParticipant = try String(
            contentsOf: projectRoot.appending(
                path: "AccountsCore/Sources/TokenStorage/TokenHoldingAccountPersistenceParticipant.swift"
            ),
            encoding: .utf8
        )
        let nftParticipant = try String(
            contentsOf: projectRoot.appending(
                path: "AccountsCore/Sources/NFTPersistence/NFTAccountPersistenceParticipant.swift"
            ),
            encoding: .utf8
        )
        let musicParticipant = try String(
            contentsOf: projectRoot.appending(
                path: "OperatorsFeature/Sources/MusicFeature/Persistence/MusicLibraryAccountPersistenceParticipant.swift"
            ),
            encoding: .utf8
        )
        let searchParticipant = try String(
            contentsOf: projectRoot.appending(
                path: "Auralis/Aura/Search/SearchHistoryAccountPersistenceParticipant.swift"
            ),
            encoding: .utf8
        )
        #expect(scopedParticipant.contains("public protocol ScopedPersistenceParticipant"))
        #expect(
            tokenParticipant.contains(
                "TokenHoldingAccountPersistenceParticipant: ScopedPersistenceParticipant"
            )
        )
        #expect(accountStorage.contains("struct TokenHoldingSnapshot") == false)
        #expect(accountStorage.contains("TokenHoldingAccountParticipant") == false)
        #expect(nftParticipant.contains("NFTAccountPersistenceParticipant: ScopedPersistenceParticipant"))
        #expect(accountStorage.contains("struct NFTSnapshot") == false)
        #expect(accountStorage.contains("NFTAccountParticipant") == false)
        #expect(
            musicParticipant.contains(
                "MusicLibraryAccountPersistenceParticipant: ScopedPersistenceParticipant"
            )
        )
        #expect(accountStorage.contains("struct MusicLibraryItemSnapshot") == false)
        #expect(accountStorage.contains("MusicLibraryAccountParticipant") == false)
        #expect(searchParticipant.contains("SearchHistoryAccountPersistenceParticipant: ScopedPersistenceParticipant"))
        #expect(accountStorage.contains("struct SearchHistorySnapshot") == false)
        #expect(accountStorage.contains("SearchHistoryAccountParticipant") == false)
    }

    @Test("shared test support does not depend on domain storage")
    func sharedTestSupportStaysDependencyClean() throws {
        let projectRoot = try projectRootURL()
        let packageRoot = projectRoot.appending(path: "AuralisTestSupport")
        let manifest = try String(
            contentsOf: packageRoot.appending(path: "Package.swift"),
            encoding: .utf8
        )
        let imports = try swiftImports(under: packageRoot.appending(path: "Sources"))

        #expect(manifest.contains("../ReceiptStorage") == false)
        #expect(imports.contains("ReceiptStorage") == false)
    }

    /// The two repository-level ownership documents, and the constraints they are required to carry.
    ///
    /// Asserted on their *content*, not merely their existence. A principle with no repository
    /// constraint attached is a preference rather than an architecture, and a file that exists but has
    /// been hollowed out would satisfy an existence check while having stopped saying anything — which
    /// is the failure mode a long-lived policy document actually has.
    @Test("the ownership documents exist and carry their required constraints")
    func ownershipDocumentsCarryTheirConstraints() throws {
        let projectRoot = try projectRootURL()
        let ownership = try String(
            contentsOf: projectRoot.appending(path: "OWNERSHIP.md"),
            encoding: .utf8
        )
        let covenant = try String(
            contentsOf: projectRoot.appending(path: "FOUNDERS_COVENANT.md"),
            encoding: .utf8
        )
        // Phrases rather than headings, so reformatting the documents does not fail this while
        // deleting a commitment does.
        let requiredOwnershipClaims = [
            "founder-owned",
            "Centralized creation does not imply permanent centralized ownership",
            "conceptually separate entities",
            "are not synonymous",
            "capable of separation from Auralis Inc",
            "real resource, right, productive asset, or coordination function",
            "do not automatically imply equity, tokens, compensation, or ownership",
            "participant ownership",
            "permanent root owner unless a named bootstrap policy",
            "outcome of maturity, not a launch feature",
            "must not depend on app composition",
            "must not default any role",
            "explicit actor, capability, policy, and resource context",
            "bootstrap exception",
            "does not grant authority by itself"
        ]
        let requiredCovenantClaims = [
            "not a legal instrument",
            "formation begins centralized",
            "not permanent ownership",
            "participants may eventually own",
            "speculative ownership abstractions",
            "reliability, security, safety, or the ability to build",
            "outcome of maturity rather than a launch feature",
            "not an enforceable legal or economic mechanism"
        ]
        let missingOwnership = requiredOwnershipClaims.filter { !ownership.contains($0) }
        let missingCovenant = requiredCovenantClaims.filter { !covenant.contains($0) }

        #expect(
            missingOwnership.isEmpty,
            "OWNERSHIP.md must keep stating these constraints: \(missingOwnership)"
        )
        #expect(
            missingCovenant.isEmpty,
            "FOUNDERS_COVENANT.md must keep stating these positions: \(missingCovenant)"
        )
    }

    /// `OWNERSHIP.md` constraint 1, as the strongest form available: the package that owns
    /// `PrincipalID` and `OwnershipDescriptor` declares **no dependencies at all**.
    ///
    /// Checked against the manifest rather than only against imports, because a dependency can be
    /// declared and not yet imported — and the moment it is declared, the "architecturally capable of
    /// separation" claim stops being structural and starts being an intention. Blockchain packages are
    /// the specific hazard: `AgentIdentityCore` was retired precisely because depending on it pulled
    /// in ENS, secp256k1 and web3.swift.
    @Test("the ownership vocabulary stays free of app and blockchain dependencies")
    func ownershipModelsHaveNoDependencies() throws {
        let projectRoot = try projectRootURL()
        let manifest = try String(
            contentsOf: projectRoot.appending(path: "AuralisFoundation/Package.swift"),
            encoding: .utf8
        )

        #expect(
            localPackageDependencies(in: manifest).isEmpty,
            "AuralisFoundation must declare no first-party package dependencies"
        )
        #expect(
            manifest.contains("url:") == false,
            "AuralisFoundation must declare no remote package dependencies"
        )

        // And the ownership sources themselves import nothing but Foundation, which is what makes the
        // vocabulary portable to a consumer that has none of this app.
        let ownershipSources = [
            "AuralisFoundation/Sources/AuralisFoundation/PrincipalID.swift",
            "AuralisFoundation/Sources/AuralisFoundation/OwnershipDescriptor.swift"
        ]
        var offenders: [String] = []

        for relativePath in ownershipSources {
            let source = try String(
                contentsOf: projectRoot.appending(path: relativePath),
                encoding: .utf8
            )
            let unexpected = importedModules(in: source).subtracting(["Foundation"])
            if unexpected.isEmpty == false {
                offenders.append("\(relativePath) imports \(unexpected.sorted())")
            }
        }

        #expect(offenders.isEmpty, "Ownership value types must import only Foundation: \(offenders)")

        let legacyOwnershipSources = [
            "AuralisPrimaryModels/Sources/AuralisPrimaryModels/PrincipalID.swift",
            "AuralisPrimaryModels/Sources/AuralisPrimaryModels/OwnershipDescriptor.swift"
        ]
        let duplicatedSources = legacyOwnershipSources.filter {
            FileManager.default.fileExists(atPath: projectRoot.appending(path: $0).path())
        }
        #expect(
            duplicatedSources.isEmpty,
            "Ownership vocabulary has one owner and must not be copied back into AuralisPrimaryModels: \(duplicatedSources)"
        )
    }

    @Test("receipt payload wire values have one receipt-owned definition")
    func receiptWireValuesBelongToReceiptsCore() throws {
        let projectRoot = try projectRootURL()
        let receiptSource = projectRoot.appending(
            path: "ReceiptsCore/Sources/ReceiptsCore/Models/ReceiptWireValues.swift"
        )
        let source = try String(contentsOf: receiptSource, encoding: .utf8)
        let legacyURL = projectRoot.appending(
            path: "AuralisPrimaryModels/Sources/AuralisPrimaryModels/ReceiptPayloadTypes.swift"
        )
        let legacySource = FileManager.default.fileExists(atPath: legacyURL.path())
            ? try String(contentsOf: legacyURL, encoding: .utf8)
            : ""

        for declaration in ["ReceiptJSONValue", "ReceiptPayload", "ReceiptMode"] {
            #expect(
                source.contains("public enum \(declaration)")
                    || source.contains("public struct \(declaration)"),
                "ReceiptsCore must own \(declaration)"
            )
        }

        let actorSource = try String(
            contentsOf: projectRoot.appending(
                path: "ReceiptsCore/Sources/ReceiptsCore/Models/ReceiptActorTypes.swift"
            ),
            encoding: .utf8
        )
        for declaration in ["ReceiptActor", "ReceiptActorDetail", "ReceiptAuthorityDetail"] {
            #expect(
                actorSource.contains("public enum \(declaration)")
                    || actorSource.contains("public struct \(declaration)"),
                "ReceiptsCore must own \(declaration)"
            )
            #expect(
                legacySource.contains("public enum \(declaration)") == false
                    && legacySource.contains("public struct \(declaration)") == false,
                "\(declaration) must not be duplicated in AuralisPrimaryModels"
            )
        }

        #expect(
            FileManager.default.fileExists(
                atPath: projectRoot.appending(
                    path: "RuntimeCore/Sources/RuntimeCore/Action/ActorRef+ReceiptActor.swift"
                ).path()
            ) == false,
            "RuntimeCore must not own receipt conversion extensions"
        )

        for declaration in ["ReceiptJSONValue", "ReceiptPayload", "ReceiptMode"] {
            #expect(
                legacySource.contains("public enum \(declaration)") == false
                    && legacySource.contains("public struct \(declaration)") == false,
                "\(declaration) must not be duplicated in AuralisPrimaryModels"
            )
        }
    }

    @Test("policy action gating uses runtime actor attribution, not receipt wire models")
    func policyActionGatingUsesRuntimeActorAttribution() throws {
        let projectRoot = try projectRootURL()
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "PolicyCore/Sources/PolicyCore/Services/PolicyActionGating.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("import RuntimeCore"))
        #expect(source.contains("actor: ActorRef"))
        #expect(
            source.contains("ReceiptActor") == false,
            "Policy authorization must accept canonical runtime attribution; receipt-shaped actor values belong at the receipt-writing boundary."
        )
    }

    /// `OWNERSHIP.md` constraint 5: ownership metadata describes relationships and grants no
    /// authority, so **no authorization decision may read an `OwnershipDescriptor`.**
    ///
    /// The scan is over the four packages that decide things — capabilities, policy, the governed
    /// runtime, and the trusted-UI approval surface. The failure this guards against is additive and
    /// plausible: a later feature wanting "the owner may do X" reaches for the descriptor that already
    /// says who the owner is, and the statement quietly becomes a key. That rule belongs in policy,
    /// with ownership as one input among several and the decision on a receipt.
    @Test("ownership metadata grants no authority")
    func ownershipMetadataGrantsNoAuthority() throws {
        let projectRoot = try projectRootURL()
        let decidingPackages = [
            "CapabilitiesCore",
            "PolicyCore",
            "RuntimeCore",
            "RuntimeKit",
            "MissionControlFeature"
        ]
        var offenders: [String] = []

        for packageName in decidingPackages {
            let sourceRoot = projectRoot.appending(path: "\(packageName)/Sources")
            guard FileManager.default.fileExists(atPath: sourceRoot.path()) else { continue }

            for fileURL in try swiftSourceFiles(under: sourceRoot) {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                guard source.contains("OwnershipDescriptor") else { continue }
                offenders.append(
                    fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: "")
                )
            }
        }

        #expect(
            offenders.isEmpty,
            "Ownership metadata is a statement, not a key: authorization must not read OwnershipDescriptor (see OWNERSHIP.md, constraint 5): \(offenders.sorted())"
        )
    }

    /// `OWNERSHIP.md` constraint 7, and the Phase 1 non-goals, pinned structurally.
    ///
    /// Contribution provenance records what happened; it must never grow a field saying what anyone is
    /// owed for it. Scanned across every first-party package source rather than only the receipt
    /// packages, because the boundary is about the *concept* and the first place it would be crossed
    /// is wherever someone decides receipts should pay out.
    @Test("no first-party package ships token, equity, or governance-weight semantics")
    func noPackageShipsOwnershipEconomics() throws {
        let projectRoot = try projectRootURL()
        let prohibited = [
            "tokensEarned",
            "equityPercentage",
            "ownershipPercentage",
            "financialReward",
            "governanceWeight",
            "vestingSchedule"
        ]
        var offenders: [String] = []

        for fileURL in try swiftSourceFiles(under: projectRoot) {
            let relativePath = fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: "")
            guard relativePath.contains("/Sources/") || relativePath.hasPrefix("Auralis/") else { continue }
            guard relativePath.contains("/.build/") == false else { continue }

            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for token in prohibited where source.contains(token) {
                offenders.append("\(relativePath): \(token)")
            }
        }

        #expect(
            offenders.isEmpty,
            "Contribution provenance and economic ownership stay separate (see OWNERSHIP.md, constraint 7): \(offenders.sorted())"
        )
    }

    @Test("operator runtime packages preserve the ADR-008 dependency direction")
    func operatorRuntimePackageDependenciesFollowLayering() throws {
        let projectRoot = try projectRootURL()
        let layers: [String: Int] = [
            "AuralisPrimaryModels": 0,
            "CapabilitiesCore": 0,
            "RuntimeCore": 1,
            "ReceiptsCore": 2,
            "ArtifactCore": 2,
            "PlaybookCore": 2,
            "PerformanceCore": 2,
            "SchedulingCore": 2,
            "ReceiptStorage": 3,
            "ArtifactStorage": 3,
            "PolicyCore": 4,
            "PlannerCore": 4,
            "AutopilotCore": 4,
            "OperatorsFeature": 5,
            "AuraUI": 5,
            "RuntimeKit": 6,
            "MissionControlFeature": 7
        ]
        var violations: [String] = []

        for (packageName, packageLayer) in layers {
            let manifestURL = projectRoot.appending(path: "\(packageName)/Package.swift")
            guard FileManager.default.fileExists(atPath: manifestURL.path()) else { continue }
            let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
            for dependency in localPackageDependencies(in: manifest) {
                guard let dependencyLayer = layers[dependency] else { continue }
                if dependencyLayer > packageLayer {
                    violations.append(
                        "\(packageName) (layer \(packageLayer)) -> \(dependency) (layer \(dependencyLayer))"
                    )
                }
            }
        }

        #expect(
            violations.isEmpty,
            "ADR-008 dependencies must point toward the same or a lower layer: \(violations.sorted())"
        )
    }

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
            .appending(path: "AccountsCore")
            .appending(path: "Package.swift")
        let packageText = try String(contentsOf: packageFile, encoding: .utf8)
        let nftSourceRoot = projectRoot.appending(path: "AccountsCore/Sources")
        let sourceImports = try [
            "NFTDomain", "NFTProviderAdapters", "NFTPersistence", "NFTPresentation", "NFTKit"
        ].reduce(into: Set<String>()) { imports, target in
            imports.formUnion(try swiftImports(under: nftSourceRoot.appending(path: target)))
        }

        #expect(packageText.contains("../ReceiptsCore"))
        #expect(packageText.contains("name: \"ReceiptStorage\""))
        #expect(sourceImports.contains("ReceiptsCore"))
        #expect(sourceImports.contains("ReceiptStorage") == false)
    }

    @Test("NFTKit layers keep one-way dependencies")
    func nftKitLayerBoundariesStayExplicit() throws {
        let projectRoot = try projectRootURL()
        let nftKitRoot = projectRoot.appending(path: "AccountsCore")
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
            domainImports.isDisjoint(with: forbiddenDomainImports),
            "NFTDomain must stay pure domain: \(domainImports.intersection(forbiddenDomainImports).sorted())"
        )
        #expect(
            providerImports.isDisjoint(with: forbiddenProviderImports),
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
            persistenceImports.isDisjoint(with: forbiddenPersistenceImports),
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
            projectRoot.appending(path: "OperatorsFeature/Sources/NFTLibraryFeature")
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
            .appending(path: "AccountsCore")
            .appending(path: "Package.swift")
        let packageText = try String(contentsOf: packageFile, encoding: .utf8)
        let sourceImports = try swiftImports(
            under: projectRoot
                .appending(path: "AccountsCore")
                .appending(path: "Sources")
                .appending(path: "TokenStorage")
        )

        #expect(packageText.contains("../NFTKit") == false)
        #expect(sourceImports.contains("NFTKit") == false)
    }

    @Test("AuraPlay receipts live in MusicFeature and playback runtime does not import NFTKit")
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
        let playbackRuntimeFile = projectRoot
            .appending(path: "Auralis")
            .appending(path: "MusicApp")
            .appending(path: "AuraPlay")
            .appending(path: "Services")
            .appending(path: "AuraPlayPlaybackRuntime.swift")
        let playbackRuntimeSource = try String(contentsOf: playbackRuntimeFile, encoding: .utf8)
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
        #expect(playbackRuntimeSource.contains("import NFTKit") == false)
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

    /// Chain identity resolves in exactly one place.
    ///
    /// Round 14 found this the expensive way: four separate copies of the friendly-name alias table
    /// had drifted apart, and the divergence was not cosmetic. `chain.inScope` canonicalizes, so a
    /// watch scoped `"ethereum"` passed its deterministic check and then matched nothing in a ledger
    /// recording `"eth-mainnet"` — the operator wrote a durable artifact and a receipt saying "no
    /// recent observed activity" against a ledger full of matching events. Silently reporting clean
    /// is the worst failure mode a monitoring operator has. One of the four copies was also
    /// *narrower* than the policy, rejecting testnets `StandardCheckConfiguration` admits.
    ///
    /// Fixing it required touching all four, and the first attempt missed one — which left the bug
    /// fully reachable through the half that runs first. So this is pinned structurally rather than
    /// trusted to review.
    @Test("chain aliases resolve only through ChainScopeReference")
    func chainAliasResolutionLivesInOnePlace() throws {
        let projectRoot = try projectRootURL()
        // The friendly names that only ever appear in an alias table. A `Chain` raw value like
        // "eth-mainnet" is deliberately not listed: matching on a canonical raw value is fine
        // anywhere, it is the *alias mapping* that must not be duplicated.
        let aliasPatterns = ["case \"ethereum\"", "case \"eth\"", "case \"mainnet\"", "case \"arbitrum\""]
        let allowedPathSuffixes: Set<String> = [
            // The one canonical resolver.
            "/RuntimeCore/Sources/RuntimeCore/Checks/ChainScopeReference.swift"
        ]
        var offenders: [String] = []

        for fileURL in try swiftSourceFiles(under: projectRoot) {
            let path = fileURL.path()
            guard !allowedPathSuffixes.contains(where: { path.hasSuffix($0) }) else { continue }
            // Tests may name aliases freely — they are asserting that resolution works.
            guard !path.contains("/Tests/"), !path.contains("/AuralisTests/"),
                  !path.contains("/AuralisUITests/") else { continue }

            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if aliasPatterns.contains(where: { source.contains($0) }) {
                offenders.append(path.replacingOccurrences(of: projectRoot.path() + "/", with: ""))
            }
        }

        #expect(
            offenders.isEmpty,
            "Chain aliases must resolve through ChainScopeReference.resolve, not a local table: \(offenders.sorted())"
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

    @Test("app source routes policy actions through RuntimeHost governance")
    func appSourceDoesNotBypassRuntimePolicyPipeline() throws {
        let projectRoot = try projectRootURL()
        let appRoot = projectRoot.appending(path: "Auralis")
        let forbiddenPatterns = [
            "ActionPolicyGate.attempt(",
            "PolicyActionGateService("
        ]
        let offenders = try swiftSourceFiles(under: appRoot)
            .filter { fileURL in
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                return forbiddenPatterns.contains { source.contains($0) }
            }
            .map { $0.path().replacingOccurrences(of: projectRoot.path() + "/", with: "") }

        #expect(
            offenders.isEmpty,
            "App source must use PipelineBackedPolicyGate/RuntimeHost so policy decisions publish runtime events and session receipts: \(offenders.sorted())"
        )
    }

    @Test("app source cannot invoke tool executors outside RuntimeHost governance")
    func appSourceDoesNotCallToolExecutorsDirectly() throws {
        let projectRoot = try projectRootURL()
        let appRoot = projectRoot.appending(path: "Auralis")
        let forbiddenPatterns = [
            "executor.execute(tool",
            ".execute(tool, proposal:"
        ]
        let offenders = try swiftSourceFiles(under: appRoot)
            .filter { fileURL in
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                return forbiddenPatterns.contains { source.contains($0) }
            }
            .map { $0.path().replacingOccurrences(of: projectRoot.path() + "/", with: "") }

        #expect(
            offenders.isEmpty,
            "ToolExecuting.execute is an internal RuntimeCore seam; app callers must enter through RuntimeHost/GovernedToolPipeline: \(offenders.sorted())"
        )
    }

    @Test("runtime sources do not open sessions with the anonymous actor")
    func runtimeSourcesDoNotAttributeWorkToAnonymousActor() throws {
        let projectRoot = try projectRootURL()
        // Only these two packages construct `AgentSession`, so this is where an anonymous actor can
        // enter the record. `ActorRef.system` decodes identically to the legacy-migration fallback in
        // `AgentSession.init(from:)` (P0.5-602), so a session opened with it is indistinguishable from
        // a row written before attribution existed — the misattribution the ticket exists to prevent.
        let runtimeRoots = [
            projectRoot.appending(path: "RuntimeKit/Sources"),
            projectRoot.appending(path: "RuntimeCore/Sources")
        ]
        let forbiddenPatterns = [
            "ActorRef.system",
            "actor: .system"
        ]
        // `ActorRef.system` is declared here; the declaration is not a call site.
        let allowedFiles: Set<String> = [
            "RuntimeCore/Sources/RuntimeCore/Actor/ActorRef.swift"
        ]

        var offenders: [String] = []
        for root in runtimeRoots {
            for fileURL in try swiftSourceFiles(under: root) {
                let relativePath = fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: "")
                guard !isAllowedPath(relativePath, allowedFiles: allowedFiles) else { continue }

                let source = try String(contentsOf: fileURL, encoding: .utf8)
                // Line-based, skipping comments: the surviving references are all prose explaining
                // why a named actor was chosen, and those must not trip the guard.
                let hasOffendingLine = source.split(separator: "\n").contains { line in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.hasPrefix("//") && !trimmed.hasPrefix("///") else { return false }
                    return forbiddenPatterns.contains { trimmed.contains($0) }
                }
                if hasOffendingLine { offenders.append(relativePath) }
            }
        }

        #expect(
            offenders.isEmpty,
            "Runtime work must be attributed to a named actor (e.g. RuntimeHost.shellContextActor), not the anonymous ActorRef.system: \(offenders.sorted())"
        )
    }

    @Test("app source cannot compose or mutate the governed runtime")
    func appSourceCannotComposeGovernedRuntime() throws {
        let projectRoot = try projectRootURL()
        let appRoot = projectRoot.appending(path: "Auralis")
        // `RuntimeTesting` is fenced alongside `RuntimeComposition`: `GovernedToolPipeline.testing` is
        // `#if DEBUG`, so without this an app or package *source* file could compose a pipeline in debug
        // builds and route around RuntimeKit. Test targets are unaffected — this walks `Sources` only.
        let forbiddenPatterns = [
            "GovernedToolPipeline(",
            "GovernedToolPipeline.testing(",
            "ToolRegistry()",
            "@_spi(RuntimeComposition) import RuntimeCore",
            "@_spi(RuntimeTesting) import RuntimeCore",
            "ToolExecutionAuthorization("
        ]
        let offenders = try swiftSourceFiles(under: appRoot)
            .filter { fileURL in
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                return forbiddenPatterns.contains { source.contains($0) }
            }
            .map { $0.path().replacingOccurrences(of: projectRoot.path() + "/", with: "") }

        #expect(
            offenders.isEmpty,
            "Only RuntimeKit composition may create registries, pipelines, or execution authorization: \(offenders.sorted())"
        )
    }

    @Test("only RuntimeKit may compose the governed runtime across first-party packages")
    func firstPartyPackagesCannotBypassRuntimeComposition() throws {
        let projectRoot = try projectRootURL()
        let packageDirectories = try FileManager.default.contentsOfDirectory(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            FileManager.default.fileExists(atPath: $0.appending(path: "Package.swift").path())
        }

        var offenders: [String] = []
        for packageDirectory in packageDirectories {
            let packageName = packageDirectory.lastPathComponent
            guard packageName != "RuntimeCore", packageName != "RuntimeKit" else { continue }
            let sources = packageDirectory.appending(path: "Sources")
            guard FileManager.default.fileExists(atPath: sources.path()) else { continue }

            for fileURL in try swiftSourceFiles(under: sources) {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                if source.contains("@_spi(RuntimeComposition) import RuntimeCore")
                    || source.contains("@_spi(RuntimeTesting) import RuntimeCore")
                    || source.contains("GovernedToolPipeline(")
                    || source.contains("GovernedToolPipeline.testing(")
                    || source.contains("ToolRegistry()")
                    || source.contains("ToolExecutionAuthorization(") {
                    offenders.append(
                        fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: "")
                    )
                }
            }
        }

        #expect(
            offenders.isEmpty,
            "Only RuntimeKit may compose RuntimeCore governance infrastructure: \(offenders.sorted())"
        )
    }

    @Test("operator and playbook packages cannot ship arbitrary platform UI")
    func operatorPackagesCannotRenderArbitraryUI() throws {
        let projectRoot = try projectRootURL()
        let governedPackages = ["OperatorCore", "OperatorsFeature", "AutopilotCore", "PlaybookCore"]
        let forbiddenImports: Set<String> = ["SwiftUI", "UIKit", "AppKit"]
        var offenders: [String] = []

        for packageName in governedPackages {
            let sourceRoot = projectRoot.appending(path: "\(packageName)/Sources")
            guard FileManager.default.fileExists(atPath: sourceRoot.path()) else { continue }

            for fileURL in try swiftSourceFiles(under: sourceRoot) {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                if !importedModules(in: source).isDisjoint(with: forbiddenImports) {
                    offenders.append(
                        fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: "")
                    )
                }
            }
        }

        #expect(
            offenders.isEmpty,
            "Operator and playbook packages must request Trusted UI schemas instead of importing platform UI: \(offenders.sorted())"
        )
    }

    @Test("every core trusted UI request has a production registry route")
    func trustedUIRequestsHaveProductionRoutes() throws {
        let projectRoot = try projectRootURL()
        let featureRoot = projectRoot.appending(path: "MissionControlFeature/Sources/MissionControlFeature")
        let productionSource = try swiftSourceFiles(under: featureRoot)
            .filter { $0.lastPathComponent != "TrustedUISurface.swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let requiredRoutes = [
            ".approveAction(",
            ".editDraft(",
            ".inspectCapability(",
            ".reviewReceipt(",
            ".inspectContextBundle("
        ]

        let missingRoutes = requiredRoutes.filter { !productionSource.contains($0) }
        #expect(
            missingRoutes.isEmpty,
            "Every TrustedUIRequest case must remain reachable through production TrustedUISurface routing: \(missingRoutes)"
        )
    }

    @Test("validated context cannot be forged outside RuntimeCore")
    func validatedContextConstructionStaysInsideRuntimeCore() throws {
        let projectRoot = try projectRootURL()
        var offenders: [String] = []

        for fileURL in try swiftSourceFiles(under: projectRoot) {
            let relativePath = fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: "")
            guard relativePath.contains("/Sources/"),
                  !relativePath.contains("/RuntimeCore/Sources/RuntimeCore/") else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains("GovernedContext(") {
                offenders.append(relativePath)
            }
        }

        #expect(
            offenders.isEmpty,
            "Only RuntimeCore may mint GovernedContext after validation: \(offenders.sorted())"
        )
    }

    @Test("model workflows cannot attach raw context dictionaries")
    func modelInferenceContextMustUseAuthorizationFactory() throws {
        let projectRoot = try projectRootURL()
        var offenders: [String] = []

        for fileURL in try swiftSourceFiles(under: projectRoot) {
            let relativePath = fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: "")
            guard relativePath.contains("/Sources/"),
                  !relativePath.contains("/RuntimeCore/Sources/RuntimeCore/") else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains("ModelInferenceRequest(") {
                offenders.append(relativePath)
            }
        }

        #expect(
            offenders.isEmpty,
            "Model workflows must use ModelInferenceRequest.authorizing with an explicit bundle and contract: \(offenders.sorted())"
        )
    }

    @Test("direct Foundation Models sessions require governed prompt construction")
    func foundationModelSessionsCannotBypassContextGovernance() throws {
        let projectRoot = try projectRootURL()
        var offenders: [String] = []

        for fileURL in try swiftSourceFiles(under: projectRoot) {
            let relativePath = fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: "")
            guard relativePath.contains("/Sources/") || relativePath.hasPrefix("Auralis/") else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            guard source.contains("LanguageModelSession(") else { continue }
            if !source.contains("ModelInferenceRequest.authorizing(")
                || source.contains("respond(to: goal.text")
                || source.contains("streamResponse(to: request.query") {
                offenders.append(relativePath)
            }
        }

        #expect(
            offenders.isEmpty,
            "Foundation Models sessions must receive prompts projected from GovernedContext: \(offenders.sorted())"
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
                rootPath: "OperatorsFeature/Sources/MusicFeature/Domain",
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
                rootPath: "OperatorsFeature/Sources/MusicFeature/Core",
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
                rootPath: "OperatorsFeature/Sources/MusicFeature/Services",
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
                rootPath: "OperatorsFeature/Sources/MusicFeature/Persistence",
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
                rootPath: "OperatorsFeature/Sources/MusicFeature/Receipts",
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
                rootPath: "OperatorsFeature/Sources/MusicFeature/Presentation",
                forbiddenImports: [
                    "NFTKit",
                    "NFTProviderAdapters",
                    "ProviderKit",
                    "ReceiptStorage"
                ],
                reason: "MusicFeature presentation may use SwiftUI and SwiftData-facing models but not provider or storage implementation packages"
            ),
            PackageSourceBoundaryRule(
                rootPath: "OperatorsFeature/Sources/MusicFeature/App",
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
                rootPath: "AccountsCore/Sources/NFTDomain",
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
                rootPath: "AccountsCore/Sources/NFTProviderAdapters",
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
                rootPath: "AccountsCore/Sources/NFTPersistence",
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
                rootPath: "AccountsCore/Sources/NFTPresentation",
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
                rootPath: "AccountsCore/Sources/NFTKit",
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
                rootPath: "AuralisFoundation/Sources/AuralisFoundation",
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
                    "UIKit",
                    // Blockchain and wallet SDKs, named explicitly because this is the package that
                    // owns `PrincipalID` and `OwnershipDescriptor`, and Phase 1 forbids the ownership
                    // vocabulary acquiring a chain dependency. `AgentIdentityCore` was retired for
                    // exactly this: depending on it pulled in ENS, secp256k1 and web3.swift, which
                    // broke `swift test` for everything downstream. A principal identifier that can
                    // only be understood by something holding a chain client is not a portable label.
                    "BigInt",
                    "ChainProviders",
                    "CoinbaseWalletSDK",
                    "DynamicSDKSwift",
                    "ENS",
                    "ExplorerAdapter",
                    "Privy",
                    "ProviderKit",
                    "Web3",
                    "WalletConnectorKit",
                    "Yttrium",
                    "reown",
                    "secp256k1",
                    "web3"
                ],
                reason: "AuralisFoundation must stay pure portable domain values with no chain or wallet dependency"
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
            projectRoot.appending(path: "OperatorsFeature/Sources/MusicFeature")
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

    /// The in-app wallet's seed-wrapping key must not be bound to the *current* biometric set.
    ///
    /// `.biometryCurrentSet` invalidates a key "if fingers are added or removed for Touch ID, or if
    /// the user re-enrolls for Face ID". That key wraps the only copy of the HD seed and the wallet
    /// has no mnemonic, so under that flag enrolling a second fingerprint — on the same device, with
    /// nothing lost or reset — permanently destroys the seed and any funds at the derived address.
    /// `InAppWalletView` discloses only the device-loss case, so it was silent as well as total.
    ///
    /// Asserted as source text because an access-control policy is fixed when the Enclave key is
    /// created and `SecAccessControl` exposes no way to read its flags back, so there is nothing to
    /// assert behaviourally. Scoped to this one file deliberately: `DataModels/Password.swift` uses
    /// `.biometryCurrentSet` legitimately, because a forgotten password can be re-entered.
    @Test("the in-app wallet seed key survives biometric re-enrollment")
    func inAppWalletKeystoreDoesNotBindToCurrentBiometricSet() throws {
        let keystore = try projectRootURL()
            .appending(path: "Auralis/Aura/WalletConnection/InAppWalletKeystore.swift")
        let source = try String(contentsOf: keystore, encoding: .utf8)

        // Comments in this file name the rejected flag when explaining the choice, so match the
        // flag as it would appear in the access-control flag list rather than anywhere in the text.
        #expect(
            source.contains("[.privateKeyUsage, .biometryCurrentSet]") == false,
            "InAppWalletKeystore must not wrap the seed with .biometryCurrentSet: adding a fingerprint would permanently destroy the only copy of the seed, and the wallet has no mnemonic to restore from."
        )
        #expect(
            source.contains("[.privateKeyUsage, .biometryAny]"),
            "InAppWalletKeystore should still require a live biometric for every use of the seed."
        )
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

    private func localPackageDependencies(in packageText: String) -> Set<String> {
        let pattern = #"\.package\s*\(\s*path:\s*\"\.\./([^\"]+)\"\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(packageText.startIndex..<packageText.endIndex, in: packageText)
        return Set(regex.matches(in: packageText, range: range).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: packageText) else { return nil }
            return String(packageText[nameRange])
        })
    }

    private func dependencyCycles(in graph: [String: Set<String>]) -> [String] {
        var visited = Set<String>()
        var active = Set<String>()
        var path: [String] = []
        var cycles = Set<String>()

        func visit(_ node: String) {
            if active.contains(node), let start = path.firstIndex(of: node) {
                cycles.insert((Array(path[start...]) + [node]).joined(separator: " -> "))
                return
            }
            guard visited.insert(node).inserted else { return }
            active.insert(node)
            path.append(node)
            for dependency in graph[node, default: []].sorted() {
                visit(dependency)
            }
            path.removeLast()
            active.remove(node)
        }

        for node in graph.keys.sorted() {
            visit(node)
        }
        return cycles.sorted()
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
