import AuralisPrimaryModels
import ImagePlayground
import OSLog
import SwiftData
import SwiftUI

struct HomeTabView: View {
    private let logger = Logger(subsystem: "Auralis", category: "HomeTabView")
    let shellStore: ShellStore
    let currentAccount: EOAccount?
    let currentAddress: String
    let currentChain: Chain
    let contextSnapshot: ContextSnapshot
    @Query private var recentStoredReceipts: [StoredReceipt]

    let router: AppRouter
    let ensResolver: any ENSResolving
    let accountStoreFactory: @MainActor (ModelContext) -> AccountStore
    let logoutCleanupServiceFactory: @MainActor (ModelContext) -> any LogoutCleaning
    let pinnedItemsStore: HomePinnedItemsStore
    @Binding var pinnedItemCount: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Namespace private var namespace
    private let transitionID = "HomeTabView"
    private let logic = HomeTabLogic()
    private let auroraArtworkSupport = HomeAuroraArtworkSupport()

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
    @State private var promptCacheOrder: [String] = []
    @State private var avatarImage: UIImage?
    @State private var pinnedActions: Set<HomeLauncherAction> = []
    @State private var scopedNFTCount = 0
    @State private var musicNFTCount = 0
    private let maxPromptCacheEntries = 32

    init(
        shellStore: ShellStore,
        currentAccount: EOAccount?,
        currentAddress: String,
        currentChain: Chain,
        contextSnapshot: ContextSnapshot,
        router: AppRouter,
        ensResolver: any ENSResolving,
        accountStoreFactory: @escaping @MainActor (ModelContext) -> AccountStore,
        logoutCleanupServiceFactory: @escaping @MainActor (ModelContext) -> any LogoutCleaning,
        pinnedItemsStore: HomePinnedItemsStore,
        pinnedItemCountBinding: Binding<Int>
    ) {
        self.shellStore = shellStore
        self.currentAccount = currentAccount
        self.currentAddress = currentAddress
        self.currentChain = currentChain
        self.contextSnapshot = contextSnapshot
        self.router = router
        self.ensResolver = ensResolver
        self.accountStoreFactory = accountStoreFactory
        self.logoutCleanupServiceFactory = logoutCleanupServiceFactory
        self.pinnedItemsStore = pinnedItemsStore
        self._pinnedItemCount = pinnedItemCountBinding

        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address ?? currentAddress) ?? ""
        let chainRawValue = currentChain.rawValue
        _recentStoredReceipts = Query(
            Self.makeRecentReceiptsDescriptor(
                accountAddress: normalizedAccountAddress,
                chainRawValue: chainRawValue
            )
        )
    }

    private var receiptScope: ReceiptTimelineScope {
        ReceiptTimelineScope(
            accountAddress: currentAccount?.address ?? currentAddress,
            chain: currentChain
        )
    }

    private var recentActivity: [ReceiptTimelineRecord] {
        recentStoredReceipts.map(ReceiptTimelineRecord.init)
    }

    private var recentActivityPreviewItems: [HomeRecentActivityPreviewItem] {
        logic.recentActivityPreviewItems(records: recentActivity)
    }

    private var nftCountRefreshKey: ScopedNFTRefreshKey {
        ScopedNFTRefreshKey(
            accountAddress: currentAccount?.address ?? currentAddress,
            chain: currentChain
        )
    }

    private static func makeRecentReceiptsDescriptor(
        accountAddress: String,
        chainRawValue: String
    ) -> FetchDescriptor<StoredReceipt> {
        var descriptor = FetchDescriptor<StoredReceipt>(
            predicate: #Predicate<StoredReceipt> { receipt in
                receipt.accountAddress == accountAddress &&
                receipt.chainRawValue == chainRawValue
            },
            sortBy: [
                SortDescriptor(\StoredReceipt.createdAt, order: .reverse),
                SortDescriptor(\StoredReceipt.sequenceID, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 5
        return descriptor
    }

    private var homeSparseDataState: HomeSparseDataState {
        logic.sparseDataState(
            scopedNFTCount: scopedNFTCount,
            recentActivityCount: recentActivity.count
        )
    }

    private var sparseStatePresentation: HomeSparseStatePresentation? {
        logic.sparseStatePresentation(
            scopedNFTCount: scopedNFTCount,
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
            scopedNFTCount: scopedNFTCount
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
                currentAccount: currentAccount,
                activeSelection: shellStore.state.selection,
                accountStoreFactory: accountStoreFactory,
                onSelectAccount: { address in
                    Task {
                        await shellStore.send(
                            .accountSelectionRequested(
                                address: address,
                                correlationID: UUID().uuidString
                            )
                        )
                    }
                },
                onRemoveAccount: { address in
                    Task {
                        await shellStore.send(
                            .activeAccountRemovalRequested(
                                address: address,
                                correlationID: UUID().uuidString
                            )
                        )
                    }
                },
                onCurrentChainChange: { chain in
                    Task {
                        await shellStore.send(
                            .chainChangeRequested(
                                chain: chain,
                                correlationID: UUID().uuidString
                            )
                        )
                    }
                }
            )
        }
        .overlay {
            if isLoading {
                loadingOverlay
            }
        }
        .alert(String(localized: "Error"), isPresented: $showErrorAlert, actions: {
            Button(String(localized: "Dismiss"), role: .cancel) {
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
        .task(id: nftCountRefreshKey) {
            await refreshScopedNFTCounts()
        }
        .task(id: nftCountRefreshKey) {
            await observeScopedNFTPersistenceChanges()
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
                title: String(localized: "Home"),
                subtitle: String(localized: "Your scoped dashboard for identity, modules, and recent local activity.")
            )

            AuraSurfaceCard(style: .soft, cornerRadius: 25, padding: 8) {
                ProfileCardView(
                    currentAccount: readOnlyCurrentAccountBinding,
                    currentAddress: readOnlyCurrentAddressBinding,
                    currentChain: currentChain,
                    scopedNFTCount: scopedNFTCount,
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
                        title: String(localized: "Active Scope"),
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
                EnergyCardView(
                    time: Date(),
                    placeholderMessage: String(
                        localized: "Preview only while live energy insights are still being connected."
                    )
                )
            }
        }
    }

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuraSectionHeader(
                title: String(localized: "Modules"),
                subtitle: homeSparseDataState == .normal
                    ? String(localized: "Core surfaces stay reachable while richer Home cards land in later passes.")
                    : String(localized: "Use the launcher routes below while this scope is still getting established.")
            ) {
                AuraPill(String(localized: "Launcher"), systemImage: "square.grid.2x2", emphasis: .accent)
            }

            tileLayout(using: modulesPresentation.primary)
        }
    }

    private var quickLinksSection: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 25) {
            VStack(alignment: .leading, spacing: 12) {
                AuraSectionHeader(
                    title: String(localized: "Quick Links"),
                    subtitle: quickLinksSubtitle
                ) {
                    AuraPill(
                        quickLinksPillTitle,
                        systemImage: pinnedItemCount > 0 ? "pin.fill" : "bolt.fill",
                        emphasis: .accent
                    )
                }

                launcherShortcuts(using: modulesPresentation.shortcuts)
            }
        }
    }

    @ViewBuilder
    private var sparseStateSection: some View {
        if let sparseStatePresentation {
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
        }
    }

    private var recentActivitySection: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 25) {
            VStack(alignment: .leading, spacing: 12) {
                AuraSectionHeader(
                    title: String(localized: "Recent Activity"),
                    subtitle: String(localized: "Latest receipts for \(contextSnapshot.scopeSummary)"),
                    trailing: {
                        Button(String(localized: "All Receipts")) {
                            router.showReceipts()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accent)
                    }
                )

                if recentActivityPreviewItems.isEmpty {
                    SecondaryText(String(localized: "No local receipt activity has been recorded for this scope yet."))
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
                    title: String(localized: "Profile Studio"),
                    subtitle: String(localized: "Temporary local controls for scenic backgrounds and device session state.")
                )

                SecondaryText(
                    String(
                        localized: "The generated profile and aurora background flow stays in Home for now and can move later without changing the dashboard shell."
                    )
                )

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
                    item.isPinned ? String(localized: "Pinned") : String(localized: "Pin"),
                    systemImage: item.isPinned ? "pin.fill" : "pin",
                    emphasis: item.isPinned ? .accent : .neutral
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                item.isPinned
                    ? String(localized: "Unpin \(item.title)")
                    : String(localized: "Pin \(item.title)")
            )
        }
        .accessibilityIdentifier(accessibilityIdentifier(for: item.action))
    }

    private var imagePreviewButton: some View {
        AuraActionButton(String(localized: "Show Image Preview"), systemImage: "photo.on.rectangle", style: .surface) {
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
        AuraActionButton(String(localized: "Logout"), systemImage: "rectangle.portrait.and.arrow.right", style: .surface) {
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

                    Text(String(localized: "No images to select"))
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

                Text(String(localized: "Generating Images..."))
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

    private func themedPrompt(
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

        let key = "\(addr)|\(chain)|\(lane.rawValue)|\(mood ?? "-")|\(intensity?.description ?? "-")|\(scene.rawValue)|\(locationHint)"
        if let cached = promptCache[key] {
            return cached
        }

        let concepts = auroraArtworkSupport
            .promptAtoms(
                address: addr,
                chainId: chain,
                lane: lane,
                mood: mood,
                intensity: intensity,
                scene: scene,
                locationHint: locationHint
            )
            .map(ImagePlaygroundConcept.text)
        cachePrompts(concepts, for: key)
        return concepts
    }

    private func cachePrompts(_ concepts: [ImagePlaygroundConcept], for key: String) {
        promptCache[key] = concepts
        promptCacheOrder.removeAll { $0 == key }
        promptCacheOrder.append(key)

        while promptCache.count > maxPromptCacheEntries, let eldestKey = promptCacheOrder.first {
            promptCacheOrder.removeFirst()
            promptCache.removeValue(forKey: eldestKey)
        }
    }

    @MainActor
    private func generateImage() async {
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

        let prompts = themedPrompt(address: currentAddress, chainId: currentChain.rawValue, lane: .poster, scene: scene)

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
            errorMessage = String(localized: "Failed to generate images. Please try again.\n\(error.localizedDescription)")
            showErrorAlert = true
        }
    }

    private func logout() {
        let plan = logic.logoutPlan()

        do {
            try logoutCleanupServiceFactory(modelContext)
                .clearLocalDataForLogout(plan: plan)
        } catch {
            logger.error("Logout cleanup failed error=\(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            showErrorAlert = true
            return
        }

        avatarImage = nil
        generatedImages = nil
        Task {
            await shellStore.send(.logoutRequested)
        }
    }

    private var sparseStateEyebrow: String {
        switch homeSparseDataState {
        case .firstRun:
            return String(localized: "First Run")
        case .sparse:
            return String(localized: "Sparse Data")
        case .normal:
            return String(localized: "Home")
        }
    }

    private var sparseStateTitle: String {
        switch homeSparseDataState {
        case .firstRun:
            return String(localized: "This Home Scope Is Ready For Its First Signal")
        case .sparse:
            return String(localized: "Home Has A Scope, But Not Much Local History Yet")
        case .normal:
            return ""
        }
    }

    private var sparseStateMessage: String {
        switch homeSparseDataState {
        case .firstRun:
            return String(
                localized: "Auralis knows who you are and which chain you are exploring, but this scope has no local NFTs or receipt activity yet. Use the next-step routes below to search, browse, or switch accounts without pretending the dashboard already has history."
            )
        case .sparse:
            return String(
                localized: "Some Home sections are still quiet for \(contextSnapshot.scopeSummary). That is an honest low-data state, not a broken dashboard. Use Search, News, or another account to keep moving while local history catches up."
            )
        case .normal:
            return ""
        }
    }

    private var quickLinksSubtitle: String {
        if pinnedItemCount > 0 {
            return String(
                localized: "\(quickLinksPillTitle) for this scope. Pinned routes: \(contextSnapshot.pinnedModuleSummary)."
            )
        }

        return String(localized: "Fast jumps into the mounted product surfaces: \(contextSnapshot.shortcutModuleSummary).")
    }

    private var quickLinksPillTitle: String {
        if pinnedItemCount > 0 {
            return String(localized: "\(pinnedItemCount) pinned")
        }

        return String(localized: "\(contextSnapshot.modulePointers.items.filter { $0.priority == .shortcut }.count) routes")
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
            return String(localized: "Open Search")
        case .switchAccount:
            return String(localized: "Switch Account")
        case .openNews:
            return String(localized: "Open News Feed")
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
        do {
            _ = try pinnedItemsStore.togglePin(action, accountAddress: currentAccount?.address ?? currentAddress)
            reloadPinnedActions()
        } catch {
            errorMessage = String(localized: "Failed to update pinned action: \(error.localizedDescription)")
            showErrorAlert = true
        }
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

    private var readOnlyCurrentAccountBinding: Binding<EOAccount?> {
        Binding(
            get: { currentAccount },
            set: { _ in }
        )
    }

    private var readOnlyCurrentAddressBinding: Binding<String> {
        Binding(
            get: { currentAddress },
            set: { _ in }
        )
    }
}

private extension HomeTabView {
    struct ScopedNFTRefreshKey: Equatable {
        let accountAddress: String
        let chain: Chain
    }

    func refreshScopedNFTCounts() async {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(currentAccount?.address ?? currentAddress) ?? ""
        let chainRawValue = currentChain.rawValue

        let scopedDescriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == normalizedAccountAddress &&
                nft.networkRawValue == chainRawValue
            }
        )
        let musicDescriptor = FetchDescriptor<NFT>(
            predicate: #Predicate<NFT> { nft in
                nft.accountAddressRawValue == normalizedAccountAddress &&
                nft.networkRawValue == chainRawValue &&
                nft.audioUrl != nil &&
                nft.audioUrl != ""
            }
        )

        do {
            let nextScopedNFTCount = try modelContext.fetchCount(scopedDescriptor)
            let nextMusicNFTCount = try modelContext.fetchCount(musicDescriptor)

            if scopedNFTCount != nextScopedNFTCount {
                scopedNFTCount = nextScopedNFTCount
            }
            if musicNFTCount != nextMusicNFTCount {
                musicNFTCount = nextMusicNFTCount
            }
        } catch {
            logger.error("Failed to refresh scoped NFT counts: \(error.localizedDescription, privacy: .public)")
        }
    }

    func observeScopedNFTPersistenceChanges() async {
        for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
            guard !Task.isCancelled else {
                return
            }
            await refreshScopedNFTCounts()
        }
    }
}
