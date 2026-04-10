import SwiftUI
import SwiftData
import ImagePlayground
import Foundation
import CryptoKit

struct HomeLogoutPlan {
    let shouldDeleteNFTs: Bool
    let shouldDeleteAccounts: Bool
    let shouldDeleteTags: Bool
    let nextCurrentAddress: String
}

enum HomeSparseDataState: Equatable {
    case firstRun
    case sparse
    case normal
}

enum HomeSparseAction: Equatable {
    case openSearch
    case switchAccount
    case openNews
}

struct HomeSparseStatePresentation: Equatable {
    let state: HomeSparseDataState
    let primaryAction: HomeSparseAction
    let secondaryAction: HomeSparseAction
}

struct HomeAccountSummaryPresentation: Equatable {
    let title: String
    let addressLine: String
    let chainTitle: String
    let trackedNFTLabel: String
    let lastActivityLabel: String?
}

struct HomeAccountSummaryInputs: Equatable {
    let accountName: String?
    let address: String
    let chain: Chain
    let scopedNFTCount: Int
    let mostRecentActivityAt: Date?
}

enum HomeLauncherAction: String, CaseIterable, Codable, Equatable, Hashable {
    case openMusic
    case openNFTTokens
    case openSearch
    case openNews
    case openReceipts
}

struct HomeLauncherItem: Equatable, Identifiable {
    let action: HomeLauncherAction
    let title: String
    let subtitle: String
    let badgeTitle: String
    let systemImage: String
    let buttonTitle: String
    let isPinned: Bool

    var id: String { title }
}

struct HomeModulesPresentation: Equatable {
    let primary: [HomeLauncherItem]
    let shortcuts: [HomeLauncherItem]
}

struct HomeRecentActivityPreviewItem: Equatable, Identifiable {
    let id: UUID
    let title: String
    let detailLine: String
    let contextLine: String
    let statusTitle: String
    let isSuccess: Bool
}

struct HomeTabLogic {
    func logoutPlan() -> HomeLogoutPlan {
        HomeLogoutPlan(
            shouldDeleteNFTs: true,
            shouldDeleteAccounts: false,
            shouldDeleteTags: true,
            nextCurrentAddress: ""
        )
    }

    func sparseDataState(
        scopedNFTCount: Int,
        recentActivityCount: Int
    ) -> HomeSparseDataState {
        if scopedNFTCount == 0 && recentActivityCount == 0 {
            return .firstRun
        }

        if scopedNFTCount == 0 || recentActivityCount == 0 {
            return .sparse
        }

        return .normal
    }

    func sparseStatePresentation(
        scopedNFTCount: Int,
        recentActivityCount: Int,
        isHomeLoading: Bool,
        isShowingFailure: Bool
    ) -> HomeSparseStatePresentation? {
        guard !isHomeLoading, !isShowingFailure else {
            return nil
        }

        switch sparseDataState(
            scopedNFTCount: scopedNFTCount,
            recentActivityCount: recentActivityCount
        ) {
        case .firstRun:
            return HomeSparseStatePresentation(
                state: .firstRun,
                primaryAction: .openSearch,
                secondaryAction: .switchAccount
            )
        case .sparse:
            return HomeSparseStatePresentation(
                state: .sparse,
                primaryAction: .openSearch,
                secondaryAction: .openNews
            )
        case .normal:
            return nil
        }
    }

    func accountSummaryPresentation(
        currentAccount: EOAccount?,
        currentAddress: String,
        currentChain: Chain,
        scopedNFTCount: Int
    ) -> HomeAccountSummaryPresentation {
        accountSummaryPresentation(
            inputs: HomeAccountSummaryInputs(
                accountName: currentAccount?.name,
                address: currentAccount?.address ?? currentAddress,
                chain: currentChain,
                scopedNFTCount: scopedNFTCount,
                mostRecentActivityAt: currentAccount?.mostRecentActivityAt
            )
        )
    }

    func accountSummaryPresentation(
        inputs: HomeAccountSummaryInputs
    ) -> HomeAccountSummaryPresentation {
        let resolvedTitle = inputs.accountName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (resolvedTitle?.isEmpty == false ? resolvedTitle! : "Active Account")
        let chainTitle = "\(inputs.chain.routingDisplayName) scope"
        let trackedNFTLabel = inputs.scopedNFTCount == 0
            ? "No scoped NFTs yet"
            : "\(inputs.scopedNFTCount) scoped NFT\(inputs.scopedNFTCount == 1 ? "" : "s")"

        let lastActivityLabel = inputs.mostRecentActivityAt.map {
            "Last active \($0.formatted(date: .abbreviated, time: .omitted))"
        }

        return HomeAccountSummaryPresentation(
            title: title,
            addressLine: inputs.address.displayAddress,
            chainTitle: chainTitle,
            trackedNFTLabel: trackedNFTLabel,
            lastActivityLabel: lastActivityLabel
        )
    }

    func modulesPresentation(
        trackCount: Int,
        pinnedActions: Set<HomeLauncherAction> = []
    ) -> HomeModulesPresentation {
        let primary = [
                HomeLauncherItem(
                    action: .openMusic,
                    title: "Music",
                    subtitle: trackCount > 0
                        ? "Local music ready: \(trackCount) track\(trackCount == 1 ? "" : "s")"
                        : "No local music tracks yet",
                    badgeTitle: trackCount > 0 ? "\(trackCount) local" : "Quiet",
                    systemImage: "play.fill",
                    buttonTitle: "Open player",
                    isPinned: pinnedActions.contains(.openMusic)
                ),
                HomeLauncherItem(
                    action: .openNFTTokens,
                    title: "NFT Tokens",
                    subtitle: "Browse NFT tokens and jump into detail",
                    badgeTitle: "Library",
                    systemImage: "square.stack",
                    buttonTitle: "Open tokens",
                    isPinned: pinnedActions.contains(.openNFTTokens)
                )
            ]
        let shortcuts = [
                HomeLauncherItem(
                    action: .openSearch,
                    title: "Search",
                    subtitle: "Open the global search tab",
                    badgeTitle: "Shell",
                    systemImage: "magnifyingglass",
                    buttonTitle: "Open Search",
                    isPinned: pinnedActions.contains(.openSearch)
                ),
                HomeLauncherItem(
                    action: .openNews,
                    title: "News Feed",
                    subtitle: "Jump to the live news surface",
                    badgeTitle: "Shell",
                    systemImage: "bubble.right",
                    buttonTitle: "Open News Feed",
                    isPinned: pinnedActions.contains(.openNews)
                ),
                HomeLauncherItem(
                    action: .openReceipts,
                    title: "Receipts",
                    subtitle: "Review local scoped activity",
                    badgeTitle: "Shell",
                    systemImage: "doc.text",
                    buttonTitle: "Open Receipts",
                    isPinned: pinnedActions.contains(.openReceipts)
                )
            ]

        return HomeModulesPresentation(
            primary: orderedByPinned(primary),
            shortcuts: orderedByPinned(shortcuts)
        )
    }

    private func orderedByPinned(_ items: [HomeLauncherItem]) -> [HomeLauncherItem] {
        let indexedItems = Array(items.enumerated())
        return indexedItems
            .sorted { lhs, rhs in
                if lhs.element.isPinned != rhs.element.isPinned {
                    return lhs.element.isPinned && !rhs.element.isPinned
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    func recentActivityPreviewItems(
        records: [ReceiptTimelineRecord],
        limit: Int = 3
    ) -> [HomeRecentActivityPreviewItem] {
        Array(records.prefix(limit)).map { record in
            let trimmedSummary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTrigger = record.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = trimmedSummary.isEmpty ? trimmedTrigger : trimmedSummary
            let detailLine: String

            if !trimmedTrigger.isEmpty, trimmedTrigger != title {
                detailLine = "\(trimmedTrigger) • \(record.createdAt.formatted(date: .omitted, time: .shortened))"
            } else {
                detailLine = "\(record.createdAt.formatted(date: .omitted, time: .shortened)) • \(record.actorTitle)"
            }

            return HomeRecentActivityPreviewItem(
                id: record.id,
                title: title.isEmpty ? record.scope : title,
                detailLine: detailLine,
                contextLine: "\(record.scope) • \(record.actorTitle)",
                statusTitle: record.statusTitle,
                isSuccess: record.isSuccess
            )
        }
    }
}

struct HomeTabView: View {
    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    @Binding var currentChainId: String
    @Binding var currentChain: Chain
    @Query private var scopedNFTs: [NFT]
    @Query(
        sort: [
            SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
            SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
        ]
    ) private var storedReceipts: [StoredReceipt]

    let onCurrentChainChanged: @MainActor (Chain, String) -> Void
    let router: AppRouter
    let ensResolver: any ENSResolving
    let services: ShellServiceHub
    let pinnedItemsStore: HomePinnedItemsStore
    @Binding var pinnedItemCount: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Namespace private var namespace
    private let transitionID = "HomeTabView"
    private let logic = HomeTabLogic()

    @State private var isPresented = false
    @State private var isLoading = false
    @State private var generatedImages: [UIImage]?
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var selectedImage: UIImage?
    @State private var scene: AuroraScene = .mountain
    @State private var showAccountSwitcher = false
    @State private var activeImageGenerationID = UUID()
    @State private var promptCache = [String: [ImagePlaygroundConcept]]()
    @State private var avatarImage: UIImage?
    @State private var pinnedActions: Set<HomeLauncherAction> = []

    init(
        currentAccount: Binding<EOAccount?>,
        currentAddress: Binding<String>,
        currentChainId: Binding<String>,
        currentChain: Binding<Chain>,
        onCurrentChainChanged: @escaping @MainActor (Chain, String) -> Void,
        router: AppRouter,
        ensResolver: any ENSResolving,
        services: ShellServiceHub,
        pinnedItemsStore: HomePinnedItemsStore,
        pinnedItemCountBinding: Binding<Int>
    ) {
        self._currentAccount = currentAccount
        self._currentAddress = currentAddress
        self._currentChainId = currentChainId
        self._currentChain = currentChain
        self.onCurrentChainChanged = onCurrentChainChanged
        self.router = router
        self.ensResolver = ensResolver
        self.services = services
        self.pinnedItemsStore = pinnedItemsStore
        self._pinnedItemCount = pinnedItemCountBinding

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount.wrappedValue?.address ?? currentAddress.wrappedValue) ?? ""
        let chainRawValue = currentChain.wrappedValue.rawValue
        _scopedNFTs = Query(
            filter: #Predicate<NFT> {
                $0.accountAddressRawValue == normalizedAccountAddress &&
                $0.networkRawValue == chainRawValue
            }
        )
    }

    private var receiptScope: ReceiptTimelineScope {
        ReceiptTimelineScope(
            accountAddress: currentAccount?.address ?? currentAddress,
            chain: currentChain
        )
    }

    private var recentActivity: [ReceiptTimelineRecord] {
        storedReceipts
            .map(ReceiptTimelineRecord.init)
            .filter { $0.matches(receiptScope) }
            .prefix(5)
            .map { $0 }
    }

    private var recentActivityPreviewItems: [HomeRecentActivityPreviewItem] {
        logic.recentActivityPreviewItems(records: recentActivity)
    }

    private var musicNFTCount: Int {
        scopedNFTs.filter { $0.isMusic() }.count
    }

    private var homeSparseDataState: HomeSparseDataState {
        logic.sparseDataState(
            scopedNFTCount: scopedNFTs.count,
            recentActivityCount: recentActivity.count
        )
    }

    private var sparseStatePresentation: HomeSparseStatePresentation? {
        logic.sparseStatePresentation(
            scopedNFTCount: scopedNFTs.count,
            recentActivityCount: recentActivity.count,
            isHomeLoading: isLoading,
            isShowingFailure: false
        )
    }

    private var modulesPresentation: HomeModulesPresentation {
        logic.modulesPresentation(
            trackCount: musicNFTCount,
            pinnedActions: pinnedActions
        )
    }

    private var accountSummaryPresentation: HomeAccountSummaryPresentation {
        logic.accountSummaryPresentation(
            currentAccount: currentAccount,
            currentAddress: currentAddress,
            currentChain: currentChain,
            scopedNFTCount: scopedNFTs.count
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identitySection
                if sparseStatePresentation != nil {
                    sparseStateSection
                }
                modulesSection
                quickLinksSection
                recentActivitySection
                creationStudioSection
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            backgroundVisual
        }
        .sheet(isPresented: $isPresented) {
            imagePreviewSheet
        }
        .sheet(isPresented: $showAccountSwitcher) {
            AccountSwitcherSheet(
                currentAccount: $currentAccount,
                currentAddress: $currentAddress,
                currentChain: $currentChain,
                accountStoreFactory: services.accountStoreFactory,
                onAccountSelectionStarted: { _ in },
                onCurrentChainChanged: onCurrentChainChanged
            )
        }
        .overlay {
            if isLoading {
                loadingOverlay
            }
        }
        .alert("Error", isPresented: $showErrorAlert, actions: {
            Button("Dismiss", role: .cancel) {
                showErrorAlert = false
            }
        }, message: {
            if let errorMessage {
                Text(errorMessage)
            }
        })
        .onAppear {
            reloadPinnedActions()
        }
        .onChange(of: currentAddress) { _, _ in
            reloadPinnedActions()
        }
    }

    private var backgroundVisual: some View {
        Group {
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
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuraSectionHeader(
                title: "Home",
                subtitle: "Your scoped dashboard for identity, modules, and recent local activity."
            )

            AuraSurfaceCard(style: .soft, cornerRadius: 25, padding: 8) {
                ProfileCardView(
                    currentAccount: $currentAccount,
                    currentAddress: $currentAddress,
                    currentChain: currentChain,
                    scopedNFTCount: scopedNFTs.count,
                    avatarImage: $avatarImage,
                    ensResolver: ensResolver,
                    onOpenAccountSwitcher: {
                        showAccountSwitcher = true
                    }
                )
            }

            AuraSurfaceCard(style: .soft, cornerRadius: 25) {
                VStack(alignment: .leading, spacing: 10) {
                    AuraSectionHeader(
                        title: "Active Scope",
                        subtitle: accountSummaryPresentation.chainTitle
                    ) {
                        AuraPill(
                            accountSummaryPresentation.trackedNFTLabel,
                            systemImage: "square.stack",
                            emphasis: .accent
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(accountSummaryPresentation.title)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                        Text(accountSummaryPresentation.addressLine)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        if let lastActivityLabel = accountSummaryPresentation.lastActivityLabel {
                            Text(lastActivityLabel)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }

            AuraSurfaceCard(style: .soft, cornerRadius: 25) {
                EnergyCardView(time: Date())
            }
        }
    }

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuraSectionHeader(
                title: "Modules",
                subtitle: homeSparseDataState == .normal
                    ? "Core surfaces stay reachable while richer Home cards land in later passes."
                    : "Use the launcher routes below while this scope is still getting established."
            ) {
                AuraPill("Launcher", systemImage: "square.grid.2x2", emphasis: .accent)
            }

            tileLayout(using: modulesPresentation.primary)
        }
    }

    private var quickLinksSection: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 25) {
            VStack(alignment: .leading, spacing: 12) {
                AuraSectionHeader(
                    title: "Quick Links",
                    subtitle: pinnedItemCount > 0
                        ? "\(pinnedItemCount) pinned link\(pinnedItemCount == 1 ? "" : "s") for this scope."
                        : "Fast jumps into the other mounted product surfaces."
                ) {
                    AuraPill(
                        pinnedItemCount > 0 ? "\(pinnedItemCount) pinned" : "Ready",
                        systemImage: pinnedItemCount > 0 ? "pin.fill" : "bolt.fill",
                        emphasis: .accent
                    )
                }

                launcherShortcuts(using: modulesPresentation.shortcuts)
            }
        }
    }

    private var sparseStateSection: some View {
        guard let sparseStatePresentation else {
            return AnyView(EmptyView())
        }

        return AnyView(
            AuraEmptyState(
            eyebrow: sparseStateEyebrow,
            title: sparseStateTitle,
            message: sparseStateMessage,
            systemImage: sparseStateSystemImage,
            tone: .neutral,
            primaryAction: AuraFeedbackAction(
                title: title(for: sparseStatePresentation.primaryAction),
                systemImage: systemImage(for: sparseStatePresentation.primaryAction),
                handler: { runSparseAction(sparseStatePresentation.primaryAction) }
            ),
            secondaryAction: AuraFeedbackAction(
                title: title(for: sparseStatePresentation.secondaryAction),
                systemImage: systemImage(for: sparseStatePresentation.secondaryAction),
                handler: { runSparseAction(sparseStatePresentation.secondaryAction) }
            )
        )
        .accessibilityIdentifier("home.sparseState")
        )
    }

    private var recentActivitySection: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 25) {
            VStack(alignment: .leading, spacing: 12) {
                AuraSectionHeader(
                    title: "Recent Activity",
                    subtitle: "Latest receipts for \(receiptScope.displayLabel)",
                    trailing: {
                        Button("All Receipts") {
                            router.showReceipts()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accent)
                    }
                )

                if recentActivityPreviewItems.isEmpty {
                    SecondaryText("No local receipt activity has been recorded for this scope yet.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(recentActivityPreviewItems) { item in
                            Button {
                                router.showReceipt(id: item.id.uuidString)
                            } label: {
                                HomeReceiptPreviewRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("home.recentActivity.\(item.id.uuidString)")
                        }
                    }
                }
            }
        }
    }

    private var creationStudioSection: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 25) {
            VStack(alignment: .leading, spacing: 12) {
                AuraSectionHeader(
                    title: "Profile Studio",
                    subtitle: "Temporary local controls for scenic backgrounds and device session state."
                )

                SecondaryText("The generated profile and aurora background flow stays in Home for now and can move later without changing the dashboard shell.")

                if shouldStackTiles {
                    VStack(spacing: 10) {
                        imagePreviewButton
                        logoutButton
                    }
                } else {
                    HStack(spacing: 10) {
                        imagePreviewButton
                        logoutButton
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tileLayout(using items: [HomeLauncherItem]) -> some View {
        if shouldStackTiles {
            VStack(spacing: 12) {
                ForEach(items) { item in
                    launcherTile(for: item)
                }
            }
        } else {
            HStack(spacing: 12) {
                ForEach(items) { item in
                    launcherTile(for: item)
                }
            }
        }
    }

    private func launcherTile(for item: HomeLauncherItem) -> some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 25) {
            HomeModuleCardView(item: item) {
                runLauncherAction(item.action)
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier(for: item.action))
    }

    @ViewBuilder
    private func launcherShortcuts(using items: [HomeLauncherItem]) -> some View {
        if shouldStackTiles {
            VStack(spacing: 10) {
                ForEach(items) { item in
                    launcherShortcutButton(for: item)
                }
            }
        } else {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    launcherShortcutButton(for: item)
                }
            }
        }
    }

    private func launcherShortcutButton(for item: HomeLauncherItem) -> some View {
        HStack(spacing: 10) {
            AuraActionButton(item.buttonTitle, systemImage: item.systemImage, style: .surface) {
                runLauncherAction(item.action)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                togglePin(for: item.action)
            } label: {
                AuraPill(
                    item.isPinned ? "Pinned" : "Pin",
                    systemImage: item.isPinned ? "pin.fill" : "pin",
                    emphasis: item.isPinned ? .accent : .neutral
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isPinned ? "Unpin \(item.title)" : "Pin \(item.title)")
        }
        .accessibilityIdentifier(accessibilityIdentifier(for: item.action))
    }

    private var imagePreviewButton: some View {
        AuraActionButton("Show Image Preview", systemImage: "photo.on.rectangle", style: .surface) {
            Task {
                if generatedImages?.isEmpty != false {
                    await generateImage()
                }

                guard generatedImages?.isEmpty == false else {
                    return
                }

                isPresented = true
            }
        }
        .accessibilityIdentifier("home.showImagePreview")
        .disabled(isLoading)
    }

    private var logoutButton: some View {
        AuraActionButton("Logout", systemImage: "rectangle.portrait.and.arrow.right", style: .surface) {
            logout()
        }
        .accessibilityIdentifier("home.logout")
    }

    private var imagePreviewSheet: some View {
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
                    SystemImage("photo.on.rectangle")
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

    private var loadingOverlay: some View {
        ZStack {
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

    private var shouldStackTiles: Bool {
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    @discardableResult
    func themedPrompt(
        address: String,
        chainId: String,
        lane: AuroraLane = .photoreal,
        mood: String? = nil,
        intensity: Double? = nil,
        scene: AuroraScene = .prairie,
        locationHint: String = "Alberta night sky"
    ) -> [ImagePlaygroundConcept] {
        let addr = address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let chain = chainId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let hasValidAddr = addr.isValidEthAddress()
        let key = "\(addr)|\(chain)|\(lane.rawValue)|\(mood ?? "-")|\(intensity?.description ?? "-")|\(scene.rawValue)|\(locationHint)"
        if let cached = promptCache[key] {
            return cached
        }

        let bytes = (addr + "|" + chain).seedBytes

        @inline(__always)
        func pick<T>(_ arr: [T], _ byteIndex: Int) -> T {
            arr[Int(bytes[byteIndex]) % arr.count]
        }

        let moodAtom = (mood?.isEmpty == false ? mood! : pick(AuroraConfig.moods, 5))
        let motif = AuroraConfig.chainThemes[chain] ?? "natural light physics emphasis"
        let chainBias: Double = ["1", "mainnet", "ethereum", "10", "42161", "8453", "137"].contains(chain) ? 0.15 : 0.0
        let seededIntensity = Double(bytes[9]) / 255.0
        let kpi = max(0, min(1, (intensity ?? seededIntensity) + chainBias))

        let comp = pick(AuroraConfig.compositions, 3)
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

        let addrBody = hasValidAddr ? String(addr.dropFirst(2)) : ""
        let addrSeg = String(addrBody.prefix(12))
        let segBytes = addrSeg.seedBytes
        let waveFreq = 0.5 + Double(segBytes[0] % 100) / 100.0
        let filament = ["fine filaments", "broad curtains", "braided strands", "diffuse veil"][Int(segBytes[1]) % 4]
        let patternAtom = hasValidAddr
            ? "address-encoded \(filament), wave frequency \(String(format: "%.2f", waveFreq))"
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
            switch kpi {
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

    @MainActor
    func generateImage() async {
        let generationID = UUID()
        activeImageGenerationID = generationID
        isLoading = true
        selectedImage = nil
        generatedImages = nil
        defer {
            if activeImageGenerationID == generationID {
                isLoading = false
            }
        }

        let prompts = themedPrompt(address: currentAddress, chainId: currentChainId, lane: .poster, scene: scene)

        do {
            let imageCreator = try await ImageCreator()
            var newImages: [UIImage] = []
            let images = imageCreator.images(
                for: prompts,
                style: .illustration,
                limit: 9
            )

            for try await image in images {
                try Task.checkCancellation()
                guard activeImageGenerationID == generationID else {
                    return
                }

                newImages.append(UIImage(cgImage: image.cgImage))
                generatedImages = newImages
            }
        } catch ImageCreator.Error.notSupported {
            guard activeImageGenerationID == generationID else {
                return
            }
            generatedImages = nil
        } catch {
            guard activeImageGenerationID == generationID else {
                return
            }
            errorMessage = "Failed to generate images. Please try again.\n\(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func logout() {
        let plan = logic.logoutPlan()

        if plan.shouldDeleteNFTs {
            try? modelContext.delete(model: NFT.self)
        }

        if plan.shouldDeleteAccounts {
            try? modelContext.delete(model: EOAccount.self)
        }

        if plan.shouldDeleteTags {
            try? modelContext.delete(model: Tag.self)
        }

        currentAccount = nil
        currentAddress = plan.nextCurrentAddress
        avatarImage = nil
        generatedImages = nil
    }

    private var sparseStateEyebrow: String {
        switch homeSparseDataState {
        case .firstRun:
            return "First Run"
        case .sparse:
            return "Sparse Data"
        case .normal:
            return "Home"
        }
    }

    private var sparseStateTitle: String {
        switch homeSparseDataState {
        case .firstRun:
            return "This Home Scope Is Ready For Its First Signal"
        case .sparse:
            return "Home Has A Scope, But Not Much Local History Yet"
        case .normal:
            return ""
        }
    }

    private var sparseStateMessage: String {
        switch homeSparseDataState {
        case .firstRun:
            return "Auralis knows who you are and which chain you are exploring, but this scope has no local NFTs or receipt activity yet. Use the next-step routes below to search, browse, or switch accounts without pretending the dashboard already has history."
        case .sparse:
            return "Some Home sections are still quiet for \(receiptScope.displayLabel). That is an honest low-data state, not a broken dashboard. Use Search, News, or another account to keep moving while local history catches up."
        case .normal:
            return ""
        }
    }

    private var sparseStateSystemImage: String {
        switch homeSparseDataState {
        case .firstRun:
            return "sparkles.rectangle.stack"
        case .sparse:
            return "square.stack.3d.up.slash"
        case .normal:
            return "house"
        }
    }

    private func title(for action: HomeSparseAction) -> String {
        switch action {
        case .openSearch:
            return "Open Search"
        case .switchAccount:
            return "Switch Account"
        case .openNews:
            return "Open News Feed"
        }
    }

    private func systemImage(for action: HomeSparseAction) -> String {
        switch action {
        case .openSearch:
            return "magnifyingglass"
        case .switchAccount:
            return "person.crop.circle.badge.arrow.forward"
        case .openNews:
            return "bubble.right"
        }
    }

    private func runSparseAction(_ action: HomeSparseAction) {
        switch action {
        case .openSearch:
            router.showSearch()
        case .switchAccount:
            showAccountSwitcher = true
        case .openNews:
            router.selectedTab = .news
        }
    }

    private func runLauncherAction(_ action: HomeLauncherAction) {
        switch action {
        case .openMusic:
            router.showMusicLibrary()
        case .openNFTTokens:
            router.showNFTTokens()
        case .openSearch:
            router.showSearch()
        case .openNews:
            router.selectedTab = .news
        case .openReceipts:
            router.showReceipts()
        }
    }

    private func reloadPinnedActions() {
        let currentPinnedActions = pinnedItemsStore.pinnedActions(for: currentAccount?.address ?? currentAddress)
        pinnedActions = currentPinnedActions
        pinnedItemCount = currentPinnedActions.count
    }

    private func togglePin(for action: HomeLauncherAction) {
        _ = pinnedItemsStore.togglePin(action, accountAddress: currentAccount?.address ?? currentAddress)
        reloadPinnedActions()
    }

    private func accessibilityIdentifier(for action: HomeLauncherAction) -> String {
        switch action {
        case .openMusic:
            return "home.openMusic"
        case .openNFTTokens:
            return "home.openNFTTokens"
        case .openSearch:
            return "home.openSearch"
        case .openNews:
            return "home.openNews"
        case .openReceipts:
            return "home.openReceipts"
        }
    }
}

extension String {
    var seedBytes: [UInt8] {
        let hash = SHA256.hash(data: Data(utf8))
        return Array(hash)
    }

    func isValidEthAddress() -> Bool {
        let text = lowercased()
        guard text.hasPrefix("0x"), text.count == 42 else {
            return false
        }

        for character in text.dropFirst(2) {
            let isHex = ("0"..."9").contains(character) || ("a"..."f").contains(character)
            if !isHex {
                return false
            }
        }

        return true
    }
}

struct HomeModuleCardView: View {
    let item: HomeLauncherItem
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuraSectionHeader(title: item.title) {
                AuraPill(item.badgeTitle, systemImage: item.systemImage, emphasis: .neutral)
            }

            VStack(alignment: .leading, spacing: 12) {
                HeadlineFontText(item.subtitle)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)

                AuraActionButton(item.buttonTitle, systemImage: item.systemImage) {
                    action()
                }
                .accessibilityLabel(item.buttonTitle)
            }
        }
    }
}

private struct HomeReceiptPreviewRow: View {
    let item: HomeRecentActivityPreviewItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AuraPill(
                item.statusTitle,
                systemImage: item.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill",
                emphasis: item.isSuccess ? .success : .accent
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)

                Text(item.detailLine)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)

                Text(item.contextLine)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            SystemImage("chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
