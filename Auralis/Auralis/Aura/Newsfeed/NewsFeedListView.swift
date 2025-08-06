//
//  NewsFeedListView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/29/25.
//

import SwiftData
import SwiftUI
import SwiftUI

// MARK: - Liquid Glass Searchable Category Dropdown
struct LiquidGlassDropdown: View {
    // MARK: - Properties
    let dataSource: [String]
    let placeholder: String
    let onSelect: (String) -> Void

    @State private var isExpanded = false
    @State private var selectedCategory = ""
    @State private var searchQuery = ""
    @State private var highlightedIndex = -1
    @FocusState private var isSearchFocused: Bool
    @Namespace private var glassNamespace

    // Computed filtered data
    private var filteredData: [String] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dataSource
        } else {
            return dataSource.filter { category in
                category.localizedCaseInsensitiveContains(searchQuery)
            }
        }
    }

    // MARK: - Initializer
    init(
        dataSource: [String] = [
            "Technology", "Business", "Health & Fitness", "Travel", "Food & Dining",
            "Entertainment", "Sports", "Education", "Shopping", "Transportation",
            "Utilities", "Home & Garden", "Fashion", "Music", "Photography",
            "Art & Design", "Science", "History", "Literature", "Gaming",
            "Social Media", "Finance", "Real Estate", "Marketing", "Productivity"
        ],
        placeholder: String = "Select Category",
        onSelect: @escaping (String) -> Void = { _ in }
    ) {
        self.dataSource = dataSource
        self.placeholder = placeholder
        self.onSelect = onSelect
    }

    // MARK: - Body
    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                // Trigger Button
                triggerButton

                // Expanded Dropdown
                if isExpanded {
                    dropdownView
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95, anchor: .top)
                                .combined(with: .opacity)
                                .combined(with: .move(edge: .top)),
                            removal: .scale(scale: 0.95, anchor: .top)
                                .combined(with: .opacity)
                        ))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
        .padding(.horizontal, 20)
    }

    // MARK: - Trigger Button
    private var triggerButton: some View {
        Button(action: toggleDropdown) {
            HStack {
                Text(selectedCategory.isEmpty ? placeholder : selectedCategory)
                    .foregroundStyle(selectedCategory.isEmpty ? .secondary : .primary)
                    .font(.system(.body, design: .rounded, weight: .medium))

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 48)
        }
        .glassEffect(.regular.tint(.blue.opacity(0.6)).interactive())
        .glassEffectID("dropdown-trigger", in: glassNamespace)
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
    }

    // MARK: - Dropdown View
    private var dropdownView: some View {
        VStack(spacing: 0) {
            // Search Bar Section
            searchBarSection
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Divider()
                .background(.primary.opacity(0.1))
                .padding(.horizontal, 16)

            // Category List
            categoryList
        }
        .glassEffectID("dropdown-content", in: glassNamespace)
        .padding(.top, 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }

    // MARK: - Search Bar Section
    private var searchBarSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(.callout, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search categories...", text: $searchQuery)
                .font(.system(.body, design: .rounded))
                .focused($isSearchFocused)
                .textFieldStyle(.plain)
                .onSubmit {
                    if !filteredData.isEmpty && highlightedIndex == -1 {
                        selectCategory(filteredData[0])
                    } else if highlightedIndex >= 0 && highlightedIndex < filteredData.count {
                        selectCategory(filteredData[highlightedIndex])
                    }
                }

            if !searchQuery.isEmpty {
                Button(action: { searchQuery = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.callout, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.white.opacity(0.1)).interactive())
        .glassEffectID("search-bar", in: glassNamespace)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchQuery.isEmpty)
    }

    // MARK: - Category List
    private var categoryList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    if filteredData.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(Array(filteredData.enumerated()), id: \.element) { index, category in
                            categoryRow(category: category, index: index)
                                .id(index)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 240)
            .onChange(of: highlightedIndex) { _, newValue in
                if newValue >= 0 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Category Row
    private func categoryRow(category: String, index: Int) -> some View {
        Button(action: { selectCategory(category) }) {
            HStack {
                HStack(spacing: 8) {
                    if selectedCategory == category {
                        Circle()
                            .fill(.tint)
                            .frame(width: 6, height: 6)
                            .transition(.scale.combined(with: .opacity))
                    }

                    Text(category)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(height: 48)
        }
        .glassEffect(
            highlightedIndex == index || selectedCategory == category
                ? .regular.tint(.white.opacity(0.2)).interactive()
                : .regular.tint(.clear).interactive()
        )
        .glassEffectID("category-\(index)", in: glassNamespace)
        .onHover { isHovering in
            if isHovering {
                highlightedIndex = index
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.02), value: filteredData)
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(.title2, weight: .light))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("No categories found")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Try adjusting your search")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 32)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Actions
    private func toggleDropdown() {
        isExpanded.toggle()
        if !isExpanded {
            searchQuery = ""
            highlightedIndex = -1
        }
    }

    private func selectCategory(_ category: String) {
        selectedCategory = category
        isExpanded = false
        searchQuery = ""
        highlightedIndex = -1
        onSelect(category)
    }
}

// MARK: - Demo View
struct LiquidGlassDropdownDemo: View {
    @State private var selectedCategory = ""

    var body: some View {
        LiquidGlassDropdown { category in
            selectedCategory = category
            print("Selected category: \\(category)")
        }
    }
}

// MARK: - Preview
#Preview {
    LiquidGlassDropdownDemo()
        .preferredColorScheme(.dark)
}
struct NewsFeedListView: View {
    @Query private var collections: [NFT.Collection]
    @Environment(\.modelContext) private var modelContext
    @Binding var currentAccount: EOAccount?
    @Binding var selectedNFT: NFT?
    @Binding var currentChain: Chain
    @State private var sortOrder = SortDescriptor(\NFT.acquiredAt?.blockTimestamp)
    @State private var searchText: String = ""

    let nftService: NFTService

    var body: some View {
        VStack {
            //    * [#11] Filter by Collection: Optional dropdown or search bar
            //    * [#12] Filter by Tag: Filter by user-added tags

            //    * AURA-13 [BE]: Implement filtering logic in the data layer.

//            * Date range filtering
//            * Multiple filter combinations
//            * Clear filters option
//            * Filter state persistence

//=================================




            ForEach(collections) { collection in
                Text(collection.name ?? "NO NAME")
                    .foregroundStyle(Color.textPrimary)
            }
            if collections.isEmpty {
                Text("No collections found")
            }
            NewsFeedListingView(
                currentAccount: $currentAccount,
                selectedNFT: $selectedNFT,
                sort: sortOrder,
                searchString: searchText,
                nftService: nftService,
                currentChain: $currentChain
            )
        }
        .toolbar {
            ToolbarItemGroup {
//                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // Sort options
                        Menu("Time", systemImage: "clock") {
                            NFTSortButton(title: "Last Update", sortOrder: $sortOrder, keyPath: \.timeLastUpdated)
                            NFTSortButton(title: "Acquired", sortOrder: $sortOrder, keyPath: \.acquiredAt?.blockTimestamp)
                        }

                        NFTSortButton(title: "Collection Name", sortOrder: $sortOrder, keyPath: \.collection?.name)
                        NFTSortButton(title: "Item Name", sortOrder: $sortOrder, keyPath: \.name)
                    } label: {
                        SystemImage("line.3.horizontal.decrease")
                            .padding(8)
                    }
//                }
//                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        // Sort options
                        //                    Menu("Time", systemImage: "clock") {
                        //                        NFTSortButton(title: "Last Update", sortOrder: $sortOrder, keyPath: \.timeLastUpdated)
                        NFTSortButton(title: "Acquired", sortOrder: $sortOrder, keyPath: \.acquiredAt?.blockTimestamp)
                        //                    }

                        NFTSortButton(title: "Collection Name", sortOrder: $sortOrder, keyPath: \.collection?.name)
                        NFTSortButton(title: "Item Name", sortOrder: $sortOrder, keyPath: \.name)
                    } label: {
                        SystemImage("ellipsis")
                            .padding(8)
                    }
//                }
            }

            ToolbarSpacer(.flexible)

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    Task {
                        await nftService.refreshNFTs(
                            for: currentAccount,
                            chain: currentChain,
                            modelContext: modelContext
                        )
                    }
                }) {
                    SystemImage("arrow.clockwise")
                }
                .disabled(nftService.isLoading)
            }
        }
    }
}
