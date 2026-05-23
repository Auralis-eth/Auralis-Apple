# Auralis Accessibility Tickets

Generated: May 23, 2026  
Source: Project-wide accessibility audit (three passes)  
Overall Grade: **C**  
Total Tickets: **36**

---

## Summary

| Priority | Count |
|----------|-------|
| Critical | 9 |
| High | 11 |
| Medium | 10 |
| Low / Polish | 6 |

Nutrition Label claims are **blocked** for: VoiceOver, Voice Control, Larger Text, Sufficient Contrast, Reduced Motion, and Differentiate Without Color until all Critical and High tickets are resolved and common-task manual testing passes on device.

---

## Completion Gate

The accessibility work is complete only when all of the following are true:

- [ ] Every Critical and High ticket is implemented, verified, and checked off.
- [ ] Every Medium ticket is either implemented or explicitly deferred with a tracked follow-up and release-risk note.
- [ ] Every Low / Polish ticket is either implemented, converted into a process artifact, or moved into the post-release backlog.
- [ ] The project builds successfully with the `Auralis` scheme.
- [ ] Targeted UI tests or Swift Testing coverage exists for code paths that can regress without visual review.
- [ ] `performAccessibilityAudit` UI tests cover the critical flows where iOS 17+ is available.
- [ ] Manual testing passes on a physical device for VoiceOver, Voice Control with Show Names, Switch Control scan order, Dynamic Type `.accessibility5`, Increase Contrast, Reduce Motion, Reduce Transparency, Grayscale, Bold Text, hardware keyboard navigation, and the QR scanner path.
- [ ] Accessibility Nutrition Label claims are reviewed only after the gate above passes.

---

## Implementation Readiness Map

| Ticket | Type | Readiness |
|--------|------|-----------|
| ACCS-001 | Implementation | Ready |
| ACCS-002 | Implementation | Ready |
| ACCS-003 | Implementation | Ready |
| ACCS-004 | Implementation | Ready |
| ACCS-005 | Implementation | Ready |
| ACCS-006 | Implementation | Ready |
| ACCS-007 | Implementation | Ready |
| ACCS-008 | Implementation | Ready, design-system-first |
| ACCS-009 | Implementation | Ready |
| ACCS-010 | Implementation | Ready |
| ACCS-011 | Implementation | Ready |
| ACCS-012 | Implementation | Needs call-site inventory before final patch |
| ACCS-013 | Implementation | Ready |
| ACCS-014 | Implementation | Needs color-token strategy decision before final patch |
| ACCS-015 | Implementation | Ready, file-by-file |
| ACCS-016 | Implementation | Ready |
| ACCS-017 | Implementation | Ready |
| ACCS-018 | Implementation | Ready |
| ACCS-019 | Implementation | Ready |
| ACCS-020 | Implementation | Ready |
| ACCS-021 | Implementation | Ready |
| ACCS-022 | Implementation | Ready after ACCS-008 surface fallback lands |
| ACCS-023 | Implementation | Ready |
| ACCS-024 | Implementation | Ready |
| ACCS-025 | Implementation | Ready |
| ACCS-026 | Implementation | Ready, file-by-file |
| ACCS-027 | Investigation | Confirm active product path before changing legacy code |
| ACCS-028 | Investigation | Requires UIKit scanner audit on device |
| ACCS-029 | Implementation | Ready with design review for which assets should scale |
| ACCS-030 | Implementation | Needs animation/haptics inventory before final patch |
| ACCS-031 | Testing | Ready |
| ACCS-032 | Testing | Ready |
| ACCS-033 | Implementation | Needs localization convention decision before broad patch |
| ACCS-034 | Implementation | Ready |
| ACCS-035 | Design Review | Needs visual design decision before implementation |
| ACCS-036 | QA / Process | Ready |

---

## Phase 1 — Critical Usability

---

### ACCS-001 · Gateway layout breaks at accessibility text sizes

**Severity:** Critical  
**Area:** Dynamic Type · Forms · Motor Accessibility  
**Files:**
- `AccountsFeature/Sources/AccountsFeature/Presentation/AddressTextField.swift` (lines 504–561)
- `AccountsFeature/Sources/AccountsFeature/Presentation/AccountsScenicScreen.swift` (line 168)

**Problem:**  
The onboarding gateway has no outer `ScrollView`. The QR scanner and address field are forced into a horizontal `HStack`. At accessibility text sizes the layout overflows vertically and horizontally, making the submit button and validation messages unreachable. Guest pass cards in the same flow use fixed-width horizontal carousel cards that do not adapt.

**Who is affected:** Large Text users, VoiceOver users, Switch Control users, users on smaller devices.

**Acceptance Criteria:**
- [x] Gateway content is wrapped in a `ScrollView`
- [x] QR/input row switches to `VStack` when `dynamicTypeSize.isAccessibilitySize` (or uses `ViewThatFits`)
- [x] Submit button and validation messages remain in the scrollable region
- [x] Guest pass carousel switches to a vertical layout at accessibility sizes
- [x] Keyboard dismissal uses `.scrollDismissesKeyboard(.interactively)`
- [x] No clipping or unreachable controls at `.accessibility3` through `.accessibility5` on a 375pt-wide device

```swift
@Environment(\.dynamicTypeSize) private var dynamicTypeSize

ScrollView {
    VStack(spacing: 16) {
        AddressEntryHeaderView()
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { QRScannerView(...); AddressTextField(address: $address) }
            VStack(alignment: .leading, spacing: 12) { QRScannerView(...); AddressTextField(address: $address) }
        }
        if let validationMessage { ErrorText(validationMessage) }
        AuraActionButton("Enter Auralis", style: .hero, action: handleSubmit)
    }
}
.scrollDismissesKeyboard(.interactively)
```

---

### ACCS-002 · NFT News Feed wraps complex card in parent Button containing nested Menu

**Severity:** Critical  
**Area:** VoiceOver · Switch Control · Voice Control · Full Keyboard Access  
**Files:**
- `NFTLibraryFeature/Sources/NFTLibraryFeature/Presentation/NFTLibraryRootViews.swift` (lines 134–149)
- `NFTLibraryFeature/Sources/NFTLibraryFeature/Presentation/NFTLibraryCardView.swift` (lines 42, 141–153)

**Problem:**  
`NFTLibraryNewsFeedRootView` wraps `NFTLibraryCardView` in a parent `Button`. The child card contains a `Menu` and additional interactive controls. Nested interactive controls are unreliable in SwiftUI and produce confusing or unreachable focus order. Secondary actions (More actions, Copy ID) may be swallowed or hidden entirely.

**Who is affected:** VoiceOver, Switch Control, Voice Control, and keyboard users.

**Acceptance Criteria:**
- [x] No interactive controls nested inside a parent `Button`
- [x] Primary open action is the card's primary accessibility action
- [x] Secondary actions (Copy ID, More) are exposed as `.accessibilityAction(named:)` custom actions
- [x] VoiceOver swipe order reaches all actions without requiring the user to enter the card element

```swift
NFTLibraryCardView(nft: nft)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(NFTLibraryPresentation.displayTitle(for: nft))
    .accessibilityValue("Collection: \(nft.collection?.name ?? "Unknown Collection")")
    .accessibilityHint("Shows NFT details")
    .accessibilityAction(named: "Open details") { actions.openNFT(nft.id) }
    .accessibilityAction(named: "Copy token ID") { copyNFTIdentifier(nft.id) }
```

---

### ACCS-003 · NewsFeed toolbar icon-only controls have no accessible labels

**Severity:** Critical  
**Area:** VoiceOver · Voice Control  
**File:** `Auralis/Aura/Newsfeed/NewsFeedListView.swift` (lines 49–69)

**Problem:**  
The sort menu uses an ellipsis icon and the refresh button uses an arrow icon with no explicit `accessibilityLabel`. Assistive technologies announce symbol names or generic descriptions instead of user-facing action names.

**Who is affected:** VoiceOver and Voice Control users.

**Acceptance Criteria:**
- [x] Sort menu announces "Sort NFTs" and hints "Changes the news feed sort order"
- [x] Refresh button announces "Refresh NFTs" and hints "Fetches the latest NFTs for this wallet"
- [x] Both controls expose `.accessibilityInputLabels` for Voice Control
- [x] Both controls meet the 44×44pt minimum touch target

```swift
Menu { sortControls } label: { Image(systemName: "ellipsis").padding(8) }
    .accessibilityLabel("Sort NFTs")
    .accessibilityHint("Changes the news feed sort order")
    .accessibilityInputLabels(["Sort", "Sort NFTs"])

Button { Task { await refreshAction() } } label: { Image(systemName: "arrow.clockwise") }
    .frame(minWidth: 44, minHeight: 44)
    .accessibilityLabel("Refresh NFTs")
    .accessibilityHint("Fetches the latest NFTs for this wallet")
    .accessibilityInputLabels(["Refresh", "Refresh NFTs"])
```

---

### ACCS-004 · Generated image choices in GalleryGrid are unlabeled

**Severity:** Critical  
**Area:** VoiceOver · Images  
**File:** `Auralis/Aura/Home/GalleryGrid.swift` (line 62)

**Problem:**  
Generated image buttons have no `accessibilityLabel` or `accessibilityHint`. VoiceOver users cannot distinguish between choices or understand what selecting an image does.

**Who is affected:** VoiceOver users choosing a home background image.

**Acceptance Criteria:**
- [x] Each image button has a distinct label describing the scene and its position (e.g., "Generated Aurora image, option 2 of 4")
- [x] Each image button has a hint explaining the action ("Selects this image for the home background")
- [x] Selection state is reflected via `.accessibilityAddTraits(.isSelected)` on the chosen image

```swift
Button { onPick(image) } label: {
    Image(uiImage: image).resizable().scaledToFill().frame(height: 110)
}
.buttonStyle(.plain)
.accessibilityLabel("Generated \(selectedScene.label) image, option \(index + 1) of \(images.count)")
.accessibilityHint("Selects this image for the home background")
.accessibilityAddTraits(selectedImage == image ? .isSelected : [])
```

---

### ACCS-005 · Validation, copy, and reset state changes are visual-only (no VoiceOver announcement)

**Severity:** Critical  
**Area:** VoiceOver Announcements · Forms · Async State  
**Files:**
- `AccountsFeature/Sources/AccountsFeature/Presentation/AddressTextField.swift` (lines 520–525, 551–555)
- `NFTLibraryFeature/Sources/NFTLibraryFeature/Presentation/NFTLibraryCardView.swift` (lines 159–165)
- `Auralis/Aura/Home/HomeTabView.swift` (lines 545–560)
- `Auralis/Aura/Settings/SettingsView.swift` (lines 78, 84)

**Problem:**  
Inline validation errors, "Copied" confirmations, image generation progress, and settings reset success/failure messages are displayed visually but not announced via `UIAccessibility.post`. VoiceOver users cannot know that submission failed, an action completed, or generation finished.

**Who is affected:** VoiceOver users and anyone relying on non-visual feedback.

**Acceptance Criteria:**
- [x] Validation failure message is announced immediately via `.announcement` notification
- [x] "NFT ID copied" confirmation is announced
- [x] Settings reset success and failure messages are announced
- [x] Image generation start and completion are announced
- [x] Account resolution progress is announced on start and on error

```swift
private func announce(_ message: String) {
    #if canImport(UIKit)
    UIAccessibility.post(notification: .announcement, argument: message)
    #endif
}
```

---

### ACCS-006 · AuraEmptyState combines action buttons into a single VoiceOver element

**Severity:** Critical  
**Area:** VoiceOver · Switch Control · Voice Control  
**File:** `AuraUI/Sources/AuraUI/AuraFeedback.swift` (lines 98–115)

**Problem:**  
`AuraEmptyState` applies `.accessibilityElement(children: .combine)` to a container that includes both descriptive text and action buttons. This flattens primary and secondary action buttons into a single announcement, making retry/refresh/CTA actions unreachable as independent controls.

**Who is affected:** All assistive technology users encountering empty or error states.

**Acceptance Criteria:**
- [x] Descriptive text (icon + title + message) is combined into one element
- [x] Action buttons are **not** inside the combined group — they remain independently focusable
- [x] Each button is reachable by VoiceOver swipe, Switch Control scan, and Voice Control name
- [x] Title text carries `.isHeader` trait

```swift
VStack(alignment: .leading, spacing: 16) {
    HStack(alignment: .top, spacing: 14) {
        icon.accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 8) {
            Text(title).accessibilityAddTraits(.isHeader)
            Text(message)
        }
    }
    .accessibilityElement(children: .combine)

    HStack(spacing: 10) { primaryButton; secondaryButton }
}
.accessibilityElement(children: .contain)
```

---

### ACCS-007 · Home background imagery has no accessibility hiding or contrast safeguard

**Severity:** Critical  
**Area:** VoiceOver Semantics · Color Contrast · Reduce Transparency  
**File:** `Auralis/Aura/Home/HomeTabView.swift` (lines 225–239)

**Problem:**  
The generated or gateway scenic background images are rendered without `.accessibilityHidden(true)`. They may appear in the VoiceOver tree as meaningless elements. A fixed `Color.background.opacity(0.3)` overlay is applied on top — insufficient contrast over arbitrary generated imagery, especially at Increase Contrast or Reduce Transparency settings.

**Who is affected:** VoiceOver users, low-vision users.

**Acceptance Criteria:**
- [x] Background image is always hidden from the accessibility tree
- [x] When `accessibilityReduceTransparency || colorSchemeContrast == .increased`, background is replaced with an opaque semantic color
- [x] Text over the home background passes WCAG AA contrast at all Dynamic Type sizes

```swift
@Environment(\.accessibilityReduceTransparency) private var reduceTransparency
@Environment(\.colorSchemeContrast) private var contrast

private var backgroundVisual: some View {
    ZStack {
        if !reduceTransparency && contrast == .standard {
            selectedOrGeneratedImage.accessibilityHidden(true)
            Color.background.opacity(0.45)
        } else {
            Color(.systemBackground)
        }
    }
    .ignoresSafeArea()
}
```

---

### ACCS-008 · Reduce Transparency and Increase Contrast not handled in design system

**Severity:** Critical  
**Area:** Reduce Transparency · Sufficient Contrast · Low Vision  
**Files:**
- `AuraUI/Sources/AuraUI/AuraSurfaces.swift` (lines 33–52)
- `AccountsFeature/Sources/AccountsFeature/Presentation/GuestPassCard.swift` (lines 119–122)
- `MusicFeature/Sources/MusicFeature/Presentation/Playback/AuraPlayNowPlayingView.swift` (line 190)

**Problem:**  
Zero uses of `accessibilityReduceTransparency`, `colorSchemeContrast`, `accessibilityDifferentiateWithoutColor`, or `accessibilityShowButtonShapes` were found across the entire project. The app relies on Liquid Glass, translucent materials, white opacity strokes, and text over imagery. Text can become unreadable under certain wallpapers, system display settings, or when the user has Reduce Transparency enabled.

**Who is affected:** Low-vision users, users with contrast sensitivity, users with Reduce Transparency or Increase Contrast enabled.

**Acceptance Criteria:**
- [x] `AuraSurfaceCard` and `AuraSurfaceGlass` read `accessibilityReduceTransparency` and `colorSchemeContrast`
- [x] When either is active, an opaque `Color(.secondarySystemBackground)` fill and `Color(.separator)` border replace all glass/material/opacity treatments
- [x] `GuestPassCard` and `AuraPlayNowPlayingView` use the shared surface modifier or their own fallback
- [x] Fix is the single source of truth — not duplicated per screen

```swift
private struct AuraSurfaceGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        let needsOpaque = reduceTransparency || colorSchemeContrast == .increased
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if needsOpaque {
            content
                .background(Color(.secondarySystemBackground), in: shape)
                .overlay { shape.strokeBorder(Color(.separator), lineWidth: 1) }
        } else {
            content
                .background(Color.surface.opacity(0.7), in: shape)
                .overlay { shape.strokeBorder(.white.opacity(0.16), lineWidth: 1) }
        }
    }
}
```

---

### ACCS-009 · Search field uses long placeholder text as its only accessible label

**Severity:** Critical  
**Area:** Forms · VoiceOver · Voice Control · Localization  
**File:** `Auralis/Aura/Search/SearchRootView.swift` (lines 297–316)

**Problem:**  
The search `TextField` uses a long instructional placeholder string as its label. Once text is entered the placeholder disappears and no stable label remains. VoiceOver reads the full placeholder on focus, which is verbose and inconsistent with the visible "Query" label above the field.

**Who is affected:** VoiceOver and Voice Control users.

**Acceptance Criteria:**
- [x] Field has `.accessibilityLabel("Query")` (or localized equivalent) as the stable label
- [x] Long instruction text is moved to `.accessibilityHint`
- [x] Field has `.accessibilityValue(query.isEmpty ? "Empty" : query)`
- [x] Field uses `.submitLabel(.search)`
- [x] Accessibility identifier is `"search.queryField"`

```swift
TextField("Search ENS, wallet, contract, symbol, NFT, collection", text: $query)
    .submitLabel(.search)
    .accessibilityLabel("Query")
    .accessibilityHint("Search by ENS name, wallet address, contract, token symbol, NFT, or collection")
    .accessibilityValue(query.isEmpty ? "Empty" : query)
    .accessibilityIdentifier("search.queryField")
```

---

## Phase 2 — Design System Defaults

---

### ACCS-010 · AuraSectionHeader does not mark titles as VoiceOver headings

**Severity:** High  
**Area:** VoiceOver Navigation · Semantic Structure  
**File:** `AuraUI/Sources/AuraUI/AuraSurfaces.swift` (lines 95–99)

**Problem:**  
`AuraSectionHeader` is used on Home, Search, Gas, Receipts, NFT, Music, and Settings screens. Without `.accessibilityAddTraits(.isHeader)`, VoiceOver users cannot use the Headings rotor to jump between card sections.

**Acceptance Criteria:**
- [ ] `AuraSectionHeader.titleView` applies `.accessibilityAddTraits(.isHeader)` once, centrally
- [ ] All screens that use `AuraSectionHeader` automatically benefit — no per-call changes needed

```swift
private var titleView: some View {
    SubheadlineFontText(title)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .accessibilityAddTraits(.isHeader)
}
```

---

### ACCS-011 · AuraActionButton may render below the 44pt minimum touch target

**Severity:** High  
**Area:** Touch Target Size · Switch Control · Motor Accessibility  
**File:** `AuraUI/Sources/AuraUI/AuraActions.swift` (lines 40–58)

**Problem:**  
The `.surface` variant uses 8pt vertical padding with no `minHeight` enforced on the label container. Small-text surface buttons can render below the 44×44pt minimum target.

**Acceptance Criteria:**
- [ ] All `AuraActionButton` variants enforce `minHeight: 44` on the label container
- [ ] `.hero` retains its existing larger shape
- [ ] `.contentShape(Rectangle())` is applied so the full 44pt area is hittable

```swift
HStack(spacing: 8) { /* icon + text */ }
    .frame(maxWidth: style == .hero ? .infinity : nil, minHeight: 44)
    .padding(.horizontal, horizontalPadding)
    .padding(.vertical, verticalPadding)
    .contentShape(Rectangle())
```

---

### ACCS-012 · SystemFontText fixed-size helper blocks Dynamic Type scaling

**Severity:** High  
**Area:** Dynamic Type  
**File:** `AuraUI/Sources/AuraUI/AuraText.swift` (lines 191–205)

**Problem:**  
`SystemFontText` takes a fixed point size with no scaling. Several feature views use it for link and button text. Text rendered at fixed sizes does not grow with the user's preferred text size setting.

**Acceptance Criteria:**
- [ ] `SystemFontText` is deprecated or replaced with a Dynamic Type-safe alternative
- [ ] Replacement uses `.font(.custom(..., relativeTo:))` or `@ScaledMetric` for any exact sizing requirement
- [ ] All call sites are migrated or flagged for follow-up

```swift
public struct ScaledSystemFontText: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat
    // ...
    public var body: some View {
        Text(text).font(.system(size: size, weight: weight))
    }
}
```

---

### ACCS-013 · AuraPill can produce empty accessibility elements

**Severity:** High  
**Area:** VoiceOver Noise  
**File:** `AuraUI/Sources/AuraUI/AuraStatus.swift` (lines 55–56)

**Problem:**  
Icon-only `AuraPill` instances with no title and no caller-supplied `accessibilityLabel` expose a blank label to VoiceOver — a confusing swipe stop with no content.

**Acceptance Criteria:**
- [ ] When `title == nil && accessibilityLabel == nil`, the pill applies `.accessibilityHidden(true)` automatically
- [ ] Callers that supply a meaningful label continue to work as before
- [ ] No manual call-site changes are required for the fix to take effect

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel(title ?? accessibilityLabel ?? "")
.accessibilityHidden(title == nil && accessibilityLabel == nil)
```

---

### ACCS-014 · Hard-coded color tokens do not adapt to Increase Contrast or alternate appearances

**Severity:** High  
**Area:** Color Contrast · Dark Mode · Increase Contrast  
**File:** `AuraUI/Sources/AuraUI/AuraColors.swift` (line 53+)

**Problem:**  
All palette tokens use fixed `Color(hexString:)` values. The palette does not provide high-contrast variants and does not respond to the system Increase Contrast accessibility setting.

**Acceptance Criteria:**
- [ ] Primary text, secondary text, error, success, accent, background, and surface tokens are moved to asset catalog named colors with light, dark, and high-contrast variants — **or** are backed by semantic system colors
- [ ] Text-over-surface contrast meets WCAG AA (4.5:1 normal, 3:1 large) in all four combinations of light/dark × standard/increased contrast
- [ ] Existing call sites require no changes

---

### ACCS-015 · Compact icon-only action buttons across the app do not guarantee 44×44 hit targets

**Severity:** High  
**Area:** Touch Target Size · Motor Accessibility  
**Files:**
- `Auralis/Aura/Search/SearchRootView.swift` (lines 482–489)
- `AccountsFeature/Sources/AccountsFeature/Presentation/AddressTextField.swift` (lines 1135–1140)
- `Auralis/Aura/Home/HomeTabView.swift` (lines 474–488)
- `Auralis/Aura/Home/ProfileCardView.swift` (lines 97–103)

**Problem:**  
Trash, pin, QR, and manage-accounts icon buttons are visually small. Without an explicit minimum frame and content shape, the tappable area can fall below Apple's 44×44pt guideline.

**Acceptance Criteria:**
- [ ] Every icon-only button across the listed files has `.frame(minWidth: 44, minHeight: 44)` and `.contentShape(Rectangle())`
- [ ] Each button has an `accessibilityLabel` describing the action and the target (e.g., "Remove search history entry vitalik.eth")
- [ ] Destructive buttons have `role: .destructive`

---

## Phase 2 (Continued) — Design System & Feature Fixes

---

### ACCS-016 · Mini-player opens Now Playing through a gesture rather than a semantic Button

**Severity:** High  
**Area:** VoiceOver · Voice Control · Switch Control · Motor Accessibility  
**File:** `MusicFeature/Sources/MusicFeature/Presentation/Playback/AuraPlayMiniPlayerView.swift` (lines 29–39)

**Problem:**  
The mini-player uses `.onTapGesture` plus a named accessibility action to open Now Playing. A `named` action helps VoiceOver but does not naturally express the element as a button to Voice Control or Switch Control. The named action is a supplementary mechanism, not a substitute for clear primary semantics.

**Acceptance Criteria:**
- [ ] The tappable mini-player region is a semantic `Button` (or carries `.isButton` trait with label + value + hint)
- [ ] Playback controls (play/pause, skip) remain as independent elements outside or adjacent to the open-player button
- [ ] `accessibilityValue` announces the current track title and playback state

```swift
Button { showNowPlaying = true } label: {
    AuraPlayMiniPlayerContentView(player: player, accessoryMode: accessoryMode)
}
.buttonStyle(.plain)
.accessibilityLabel("Now Playing")
.accessibilityValue(currentTrackAccessibilityValue)
.accessibilityHint("Opens the Now Playing screen")
```

---

### ACCS-017 · Recently Played context menu actions have no accessibility alternatives; haptics bypass AuraHaptics

**Severity:** High  
**Area:** Custom Actions · Haptics · Motor Accessibility  
**File:** `MusicFeature/Sources/MusicFeature/Presentation/Playback/AuraPlayRecentlyPlayedSection.swift` (lines 51–116)

**Problem:**  
Secondary actions (Start Over, Remove) are only available via context menu long-press. The view also instantiates `UIImpactFeedbackGenerator` directly, bypassing `AuraHaptics` which properly gates haptics for Reduce Motion users.

**Acceptance Criteria:**
- [ ] Play, Start Over, and Remove are exposed as `.accessibilityAction(named:)` custom actions on each card
- [ ] Direct `UIImpactFeedbackGenerator` instantiation is replaced with `AuraHaptics`
- [ ] Context menu is retained as an enhancement — custom actions are the accessible path

```swift
AuraPlayRecentlyPlayedMiniCard(item: item) { playTapped(item: item) }
    .accessibilityAction(named: "Play") { playTapped(item: item) }
    .accessibilityAction(named: "Start over") { startOverTapped(item: item) }
    .accessibilityAction(named: "Remove from Recently Played") {
        player.auraPlayRemoveRecentlyPlayed(id: item.id)
    }
```

---

### ACCS-018 · Gas fee cards use fixed horizontal layout at accessibility text sizes

**Severity:** High  
**Area:** Dynamic Type · VoiceOver Row Grouping  
**File:** `Auralis/Gas/GasFeeEstimate.swift` (lines 341–344, 653–703)

**Problem:**  
Base fee and congestion cards are always in an `HStack`. Row bodies use `HStack` with `Spacer()` to push values to trailing edge. At accessibility sizes both layouts truncate or create confusing reading order. Trend arrows are color-and-shape-only status indicators.

**Acceptance Criteria:**
- [ ] Card pair uses `ViewThatFits` or `dynamicTypeSize.isAccessibilitySize` guard to switch to `VStack`
- [ ] Data rows use Dynamic Type-safe layout (vertical at accessibility sizes)
- [ ] Each row is combined into one element with a `.accessibilityLabel` + `.accessibilityValue` pair
- [ ] Trend arrows carry a text alternative (e.g., `.accessibilityLabel("Trending up")`) or are hidden as decorative if nearby text already communicates the trend

---

### ACCS-019 · Account rows do not expose selected state or active/inactive value to VoiceOver

**Severity:** High  
**Area:** VoiceOver Values · Selected State  
**File:** `AccountsFeature/Sources/AccountsFeature/Presentation/AddressTextField.swift` (lines 1093–1144)

**Problem:**  
The active account is shown visually with an "Active" chip, but the underlying button element does not communicate selected/active state semantically. VoiceOver users cannot tell which account is currently active without reading adjacent visual elements.

**Acceptance Criteria:**
- [ ] Active row carries `.accessibilityAddTraits(.isSelected)`
- [ ] Row value announces "Active account" or "Inactive account"
- [ ] The "Active" chip is hidden as decorative (`.accessibilityHidden(true)`) since the row element already communicates this

```swift
.accessibilityLabel(account.name ?? account.address.accountFeatureDisplayAddress)
.accessibilityValue(isActive ? "Active account" : "Inactive account")
.accessibilityAddTraits(isActive ? .isSelected : [])
```

---

### ACCS-020 · Search result rows and history rows lack combined semantics and adequate hit targets for delete

**Severity:** High  
**Area:** VoiceOver Row Semantics · Touch Targets · Custom Actions  
**File:** `Auralis/Aura/Search/SearchRootView.swift` (lines 401–490)

**Problem:**  
Search match buttons wrap a multi-line `VStack` but expose only an accessibility identifier — no label, value, or hint. History rows have a small icon-only delete button adjacent to the tap target, risking accidental activation and lacking a 44pt frame.

**Acceptance Criteria:**
- [ ] Match rows are combined with label `"\(match.kind.title), \(match.title)"`, value `match.subtitle`, and hint "Opens this result"
- [ ] History rows expose a delete custom action on the row itself
- [ ] Delete button has `.frame(minWidth: 44, minHeight: 44)` and `.accessibilityLabel("Delete \(entry.query)")`

---

## Phase 3 — Forms and Navigation

---

### ACCS-021 · Header/chrome account label truncates and omits selected chain from accessibility value

**Severity:** Medium  
**Area:** Dynamic Type · VoiceOver Values  
**File:** `Auralis/Aura/GlobalChromeView.swift` (lines 80–94)

**Problem:**  
Account title and chain names use `.lineLimit(1)` and the accessibility value omits selected chain names. Wallet identity and chain scope are core orientation data for every transaction flow.

**Acceptance Criteria:**
- [ ] Account title line limit is 2 at accessibility sizes
- [ ] Chain name text allows wrapping to 2 lines at accessibility sizes
- [ ] Button value includes `"\(accountTitle), \(selectedChainDisplayNames)"`

---

### ACCS-022 · Guest pass card contains decorative icons and risky typography semantics

**Severity:** Medium  
**Area:** VoiceOver Semantics · Dynamic Type · Contrast  
**File:** `AccountsFeature/Sources/AccountsFeature/Presentation/GuestPassCard.swift` (lines 51–122)

**Problem:**  
Role and metadata icons are not hidden or labeled. Title/subtitle use monospaced text with `tracking(2)` which reduces readability. Address label uses `.white.opacity(0.5)` — insufficient contrast. Material background has no Reduce Transparency fallback.

**Acceptance Criteria:**
- [ ] Card is a combined accessibility element with label, value, and optional `.isButton` trait
- [ ] Decorative role/metadata icons are hidden from the accessibility tree
- [ ] `tracking` modifier is removed or reduced at accessibility sizes
- [ ] Address label opacity meets AA contrast or is replaced with a semantic color
- [ ] Card background uses the shared `AuraSurfaceGlass` modifier (which handles Reduce Transparency — see ACCS-008)

---

### ACCS-023 · Home profile card avatar and loading state not semantically clear; layout fixed at large text sizes

**Severity:** Medium  
**Area:** VoiceOver Semantics · Dynamic Type  
**File:** `Auralis/Aura/Home/ProfileCardView.swift` (lines 46–70)

**Problem:**  
The avatar image, fallback icon, and ProgressView overlay have no explicit hidden or label behavior. The layout is a fixed `HStack` with a 96×96 image — at accessibility sizes, leading image plus trailing edit button squeezes the text content.

**Acceptance Criteria:**
- [ ] Avatar is `.accessibilityHidden(true)` (decorative) or carries an explicit `.accessibilityLabel` describing the account identity
- [ ] ProgressView overlay is announced via `.accessibilityLabel("Loading avatar")`
- [ ] Layout switches to vertical stacking at accessibility sizes

---

### ACCS-024 · Artwork labels are inconsistent across music and NFT surfaces

**Severity:** Medium  
**Area:** Images · VoiceOver Noise  
**Files:**
- `MusicFeature/Sources/MusicFeature/Presentation/Playback/CachedAsyncImage.swift`
- `MusicFeature/Sources/MusicFeature/Presentation/Playback/AuraPlayNowPlayingView.swift` (line ~258)
- `NFTLibraryFeature/Sources/NFTLibraryFeature/Presentation/NFTLibraryCardView.swift` (lines 56–71)

**Problem:**  
Music artwork uses a generic "Artwork" label even when a track title is available nearby. NFT images duplicate the title text already in the same cell. Neither pattern is optimal — one is too vague, the other is noisy.

**Acceptance Criteria:**
- [ ] Music artwork that is adjacent to the track name is hidden as decorative
- [ ] Where artwork is the primary or only identification, label includes the track/NFT title: `"\(trackTitle) artwork"`
- [ ] NFT card image is hidden as decorative since the combined card element carries the title

---

### ACCS-025 · Gas congestion indicator is a color/bar-only visual with no accessible alternative

**Severity:** Medium  
**Area:** Differentiate Without Color · VoiceOver Values  
**File:** `Auralis/Gas/GasFeeEstimate.swift` (lines 621–637, 697–700)

**Problem:**  
The congestion bar indicator communicates level through bar count and fill color. No text, label, or accessibility value is attached to the indicator itself.

**Acceptance Criteria:**
- [ ] Indicator is either hidden as decorative (when adjacent text already communicates congestion level) or exposes `.accessibilityLabel("Network congestion")` + `.accessibilityValue(estimate.congestionLevel.displayName)`
- [ ] Passes "Differentiate Without Color" — status is communicated without relying on color alone

---

### ACCS-026 · Horizontal carousels have no accessibility-size fallback

**Severity:** Medium  
**Area:** Dynamic Type · Switch Control · VoiceOver  
**Files:**
- `AccountsFeature/Sources/AccountsFeature/Presentation/GuestPassCarousel.swift` (lines 16–23)
- `MusicFeature/Sources/MusicFeature/Presentation/Playback/AuraPlayRecentlyPlayedSection.swift` (lines 42–50)
- `NFTLibraryFeature/Sources/NFTLibraryFeature/Presentation/NFTLibraryCardView.swift` (lines 295–310)

**Problem:**  
Horizontal-scroll carousels are efficient at default text sizes but are brittle, inefficient, and sometimes unreachable at accessibility sizes or when Switch Control is in scanning mode.

**Acceptance Criteria:**
- [ ] Each carousel checks `dynamicTypeSize.isAccessibilitySize` and switches to a vertical list or `LazyVStack` layout
- [ ] Section headers carry a count (e.g., "Recently Played, 4 items") so users know the scope before navigating

---

### ACCS-027 · Legacy playlist view has swipe-only delete with no accessibility action alternative

**Severity:** Medium  
**Area:** Custom Actions · VoiceOver · Switch Control  
**File:** `Auralis/MusicApp/AI/Audio Engine/Playlist/PlaylistListView.swift` (line 89)

**Problem:**  
Delete is only accessible via `.swipeActions`. VoiceOver and Switch Control users cannot discover or activate swipe-only actions through normal navigation.

**Acceptance Criteria:**
- [ ] If this view is still on an active product path: each row exposes `.accessibilityAction(named: "Delete playlist") { delete(playlist) }`
- [ ] If this view is legacy/dead code: file is removed or excluded from compilation

---

### ACCS-028 · External QR scanner UIKit controls need accessibility label audit

**Severity:** Medium  
**Area:** UIKit Bridge · Camera Flow · VoiceOver  
**Files:**
- `AccountsFeature/Sources/AccountsFeature/Presentation/AddressTextField.swift` (lines 683–689)
- `CodeScanner/Sources/CodeScanner/ScannerViewController.swift` (lines 119–132)

**Problem:**  
The SwiftUI wrapper labels the entry button correctly, but the UIKit scanner controls inside `ScannerViewController` are third-party/local package code. Their accessibility labels, button traits, modal focus behavior, and error state labels have not been verified.

**Acceptance Criteria:**
- [ ] Capture and gallery buttons in `ScannerViewController` have `accessibilityLabel`, `accessibilityHint`, and minimum 44pt targets
- [ ] Modal focus moves to a sensible first element on scanner presentation
- [ ] Camera permission denied and error states announce via UIKit accessibility notification
- [ ] Verified by Accessibility Inspector on a physical device

---

## Phase 4 — Visual Accessibility

---

### ACCS-029 · Fixed icon and artwork dimensions should use @ScaledMetric or Large Content Viewer

**Severity:** Medium  
**Area:** Dynamic Type · Low Vision  
**Files:**
- `Auralis/Aura/Home/ProfileCardView.swift` (96×96 avatar, line 59)
- `Auralis/Aura/Home/HomeTabView.swift` (placeholder icon `.system(size: 60)`, line 531)
- `MusicFeature/Sources/MusicFeature/Presentation/Playback/AuraPlayNowPlayingView.swift` (artwork max 280×280, line 258)

**Problem:**  
Important repeated icons and artwork frames are fixed. Non-text chrome does not always need to grow, but meaningful icons in control areas should scale or expose a Large Content Viewer at fixed sizes.

**Acceptance Criteria:**
- [ ] Icon dimensions used in interactive controls (not pure artwork) use `@ScaledMetric(relativeTo:)` or a capped scale
- [ ] Fixed-size icons in tab bars and toolbars add `.accessibilityShowsLargeContentViewer` for Large Content Viewer access
- [ ] Artwork frames (music, NFT) may remain fixed but should not clip at accessibility sizes

---

### ACCS-030 · Reduce Motion not consistently applied; some animations and haptics bypass the gating mechanism

**Severity:** Medium  
**Area:** Reduce Motion · Haptics  
**Files:**
- `Auralis/Aura/Home/HomeTabView.swift` (`.navigationTransition(.zoom(...))`, line 542)
- `MusicFeature/Sources/MusicFeature/Presentation/Playback/AuraPlayRecentlyPlayedSection.swift` (direct `UIImpactFeedbackGenerator`, lines 113–116)
- Various `withAnimation` call sites not gated by `accessibilityReduceMotion`

**Problem:**  
The app has `AuraHaptics` for gated haptics and uses `accessibilityReduceMotion` in some places, but zoom navigation transitions, several `withAnimation` calls, and the recently played haptics bypass these mechanisms.

**Acceptance Criteria:**
- [ ] Zoom navigation transition is disabled when `accessibilityReduceMotion == true`
- [ ] All `UIImpactFeedbackGenerator` calls are replaced with `AuraHaptics`
- [ ] A search of `withAnimation` call sites produces no ungated animations that involve movement or expansion at critical screen transitions

---

## Phase 5 — Accessibility Testing

---

### ACCS-031 · No accessibility preview matrix for critical screens

**Severity:** Low  
**Area:** Testing · Previews · Regression Prevention  
**Files:** Project-wide

**Problem:**  
Previews exist for many views but none systematically cover large Dynamic Type, Dark Mode with Increase Contrast, or Reduce Motion/Transparency states. Accessibility regressions are difficult to catch in code review.

**Acceptance Criteria:**
- [ ] The following screens have at least a large-text and a dark+increased-contrast preview: Gateway, Home, NewsFeed, Search, Gas, Music (mini + now playing), NFT detail, Receipts, Settings
- [ ] Design-system components (`AuraSectionHeader`, `AuraActionButton`, `AuraEmptyState`, `AuraSurfaceCard`) have `.accessibility5` previews
- [ ] Preview names follow the convention `#Preview("Large Text")` / `#Preview("Dark Increased Contrast")`

```swift
#Preview("Largest Accessibility Text") {
    HomeTabView(...).environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Dark Increased Contrast") {
    HomeTabView(...)
        .preferredColorScheme(.dark)
        .environment(\.accessibilityContrast, .increased)
}
```

---

### ACCS-032 · No automated accessibility audit tests (performAccessibilityAudit)

**Severity:** Low  
**Area:** Testing · Regression Prevention  
**Files:** `AuralisUITests/`

**Problem:**  
No uses of `performAccessibilityAudit` were found in the test targets. Automated audits catch a wide range of common issues without manual effort and can be gated in CI.

**Acceptance Criteria:**
- [ ] At least one UI test per critical flow calls `try app.performAccessibilityAudit()` where iOS ≥ 17
- [ ] Critical flows covered: Gateway, Home, NewsFeed, Search, Gas, Music, NFT, Receipts
- [ ] `performAccessibilityAudit` is guarded by `#available(iOS 17.0, *)`
- [ ] Audit issues result in test failure (not just a print)

```swift
func testGatewayAccessibilityAudit() throws {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.textFields["Ethereum Address"].exists)
    XCTAssertTrue(app.buttons["Enter Auralis"].exists)
    if #available(iOS 17.0, *) {
        try app.performAccessibilityAudit()
    }
}
```

---

### ACCS-033 · Accessibility strings are not consistently localized

**Severity:** Low  
**Area:** Localization · VoiceOver · Voice Control  
**Files:** Project-wide (examples: `GlobalChromeView.swift:61`, `SearchRootView.swift:489`, `AuraPlayNowPlayingView.swift:90`, `NFTLibraryCardView.swift:152`)

**Problem:**  
Many `accessibilityLabel`, `accessibilityHint`, and `accessibilityValue` strings are raw English literals. Newer package code uses raw strings even where SwiftUI `Text` calls use `String(localized:)`.

**Acceptance Criteria:**
- [ ] All user-facing accessibility strings use `String(localized:)` or the project's established localization convention
- [ ] A linting pass (grep for `\.accessibilityLabel("` with raw literals) finds zero unlocalized strings in AuraUI and all feature packages

---

### ACCS-034 · Redundant explicit labels on visible-text buttons may cause Voice Control drift

**Severity:** Low  
**Area:** Voice Control Polish · Localization  
**Files:**
- `AuraUI/Sources/AuraUI/AuraActions.swift` (line 49)
- `Auralis/MusicApp/AI/Audio Engine/Playlist/NewPlaylistView.swift` (lines 166, 175)

**Problem:**  
Buttons with visible text labels (e.g., "Save Playlist", "Cancel") also set `.accessibilityLabel(title)` to the same English string. This is harmless now but can cause Voice Control activation mismatches if the localized visible text diverges from the hard-coded label in a future localized build.

**Acceptance Criteria:**
- [ ] Redundant `.accessibilityLabel` overrides on buttons whose visible text is already sufficient are removed
- [ ] Explicit labels are retained only where the visible label is insufficient (icon-only or truncated)

---

### ACCS-035 · Section heading visual style is subtle — consider stronger typographic hierarchy

**Severity:** Low  
**Area:** Low Vision · Cognitive Accessibility  
**File:** `AuraUI/Sources/AuraUI/AuraSurfaces.swift` (line 96)

**Problem:**  
`AuraSectionHeader.titleView` uses `SubheadlineFontText`, which is small and light. On dense card screens many sections rely on these headers for orientation, but they can be visually easy to miss.

**Acceptance Criteria:**
- [ ] Design review evaluates `HeadlineFontText` or a semibold subheadline with stronger contrast for section headers
- [ ] Final choice is implemented in `AuraSectionHeader` — does not require per-call changes
- [ ] Change is paired with the `.isHeader` fix in ACCS-010

---

### ACCS-036 · Manual device accessibility release checklist is not documented as a formal gate

**Severity:** Low  
**Area:** QA Process · Release Readiness  
**Files:** None (process artifact)

**Problem:**  
Manual accessibility verification is referenced in audit documents but not captured as a tracked release gate. Regressions can ship undetected.

**Acceptance Criteria:**
- [ ] A `ACCESSIBILITY_RELEASE_CHECKLIST.md` is created and stored in the repo
- [ ] Checklist covers: VoiceOver (onboarding → home → search → gas → music → NFT → receipts → settings), Voice Control "Show names", Switch Control scan order, Dynamic Type `.accessibility5`, Increase Contrast, Reduce Motion, Reduce Transparency, Grayscale, Bold Text, hardware keyboard tab order, QR scanner path
- [ ] Checklist is required sign-off before each App Store submission

---

## Ticket Index

| ID | Title | Severity | Phase |
|----|-------|----------|-------|
| ACCS-001 | Gateway layout breaks at accessibility text sizes | Critical | 1 |
| ACCS-002 | NFT News Feed wraps complex card in parent Button with nested Menu | Critical | 1 |
| ACCS-003 | NewsFeed toolbar icon-only controls have no accessible labels | Critical | 1 |
| ACCS-004 | Generated image choices in GalleryGrid are unlabeled | Critical | 1 |
| ACCS-005 | Validation, copy, and reset state changes are visual-only | Critical | 1 |
| ACCS-006 | AuraEmptyState combines action buttons into a single VoiceOver element | Critical | 1 |
| ACCS-007 | Home background imagery has no accessibility hiding or contrast safeguard | Critical | 1 |
| ACCS-008 | Reduce Transparency and Increase Contrast not handled in design system | Critical | 1 |
| ACCS-009 | Search field uses long placeholder as its only accessible label | Critical | 1 |
| ACCS-010 | AuraSectionHeader does not mark titles as VoiceOver headings | High | 2 |
| ACCS-011 | AuraActionButton may render below 44pt minimum touch target | High | 2 |
| ACCS-012 | SystemFontText fixed-size helper blocks Dynamic Type scaling | High | 2 |
| ACCS-013 | AuraPill can produce empty accessibility elements | High | 2 |
| ACCS-014 | Hard-coded color tokens do not adapt to Increase Contrast | High | 2 |
| ACCS-015 | Compact icon-only buttons across the app lack 44×44 hit targets | High | 2 |
| ACCS-016 | Mini-player opens Now Playing through a gesture not a semantic Button | High | 2 |
| ACCS-017 | Recently Played context menu has no accessibility action alternatives | High | 2 |
| ACCS-018 | Gas fee cards use fixed horizontal layout at accessibility text sizes | High | 2 |
| ACCS-019 | Account rows do not expose selected/active state to VoiceOver | High | 2 |
| ACCS-020 | Search result and history rows lack combined semantics and hit targets | High | 2 |
| ACCS-021 | Chrome account label truncates and omits chain from accessibility value | Medium | 3 |
| ACCS-022 | Guest pass card has decorative icons and risky typography semantics | Medium | 3 |
| ACCS-023 | Home profile card avatar and loading state not semantically clear | Medium | 3 |
| ACCS-024 | Artwork labels are inconsistent across music and NFT surfaces | Medium | 3 |
| ACCS-025 | Gas congestion indicator is color/bar-only with no accessible alternative | Medium | 4 |
| ACCS-026 | Horizontal carousels have no accessibility-size fallback | Medium | 3 |
| ACCS-027 | Legacy playlist view has swipe-only delete with no accessibility action | Medium | 3 |
| ACCS-028 | External QR scanner UIKit controls need accessibility label audit | Medium | 3 |
| ACCS-029 | Fixed icon and artwork dimensions should use @ScaledMetric | Medium | 4 |
| ACCS-030 | Reduce Motion not consistently applied; some animations bypass gating | Medium | 4 |
| ACCS-031 | No accessibility preview matrix for critical screens | Low | 5 |
| ACCS-032 | No automated accessibility audit tests (performAccessibilityAudit) | Low | 5 |
| ACCS-033 | Accessibility strings are not consistently localized | Low | 5 |
| ACCS-034 | Redundant explicit labels on visible-text buttons may cause Voice Control drift | Low | 5 |
| ACCS-035 | Section heading visual style is subtle — consider stronger typographic hierarchy | Low | 5 |
| ACCS-036 | Manual device accessibility release checklist not documented as a formal gate | Low | 5 |
