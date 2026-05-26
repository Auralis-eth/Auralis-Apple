# Auralis Accessibility Tickets

Synthesized from three project-wide accessibility audits. Issues are deduplicated and grouped by the five-phase refactor plan. Severity is the highest rating assigned across all audits.

**Color scope:** This plan preserves the current Aura color palette. Tickets may add labels, values, focus handling, touch targets, Dynamic Type behavior, motion/transparency accommodations, and non-color cues. Color contrast is tracked only by A11Y-026 as an audit-and-ticketing pass; any actual palette, token, foreground, background, border, opacity, or asset-catalog change requires a separate follow-up ticket with product/design approval.

---

## Phase 1 — Critical Usability

### A11Y-001 · Associate validation state with `AddressTextField`

**Severity:** Critical  
**Area:** VoiceOver · Forms · Validation  
**File:** `AccountsFeature/Sources/AccountsFeature/Presentation/AddressTextField.swift`  
**Lines:** 19–33, 585–590, 612–620

**Problem**  
The `TextField` label is only the constructor title. Validation errors appear as a separate `ErrorText` view below the field; they are not associated with the field element itself. VoiceOver focus on the field does not expose whether the current value is invalid, and submit failures are not announced at the point validation is set.

**Acceptance criteria**
- [ ] `AddressTextField` accepts a `validationMessage: String?` parameter
- [ ] `.accessibilityLabel`, `.accessibilityValue`, and `.accessibilityHint` are set on the field; hint surfaces `validationMessage` when present
- [ ] `.accessibilityInputLabels` includes common synonyms ("Wallet address", "ENS name")
- [ ] Validation failure calls `AuraAccessibilityAnnouncer.announce(message)`
- [ ] Focus returns to the field after a failed submit

**Reference implementation**
```swift
TextField("Ethereum address", text: $address)
    .accessibilityLabel("Ethereum address")
    .accessibilityValue(address.isEmpty ? "Empty" : address)
    .accessibilityHint(validationMessage ?? "Enter an ENS name or EVM wallet address.")
    .accessibilityInputLabels(["Ethereum address", "Wallet address", "ENS name"])
```

---

### A11Y-003 · Label and announce bootstrap and overlay loading states

**Severity:** Critical  
**Area:** VoiceOver · Loading States · Focus  
**Files:** `Auralis/Auralis/Aura/MainAuraView.swift` (lines 138–152, 180–190), `Auralis/Auralis/Aura/Home/HomeTabView.swift` (lines 215–219, 577–594)

**Problem**  
The bootstrap `ProgressView()` has no label. The image-generation overlay combines a spinner and text visually but does not mark itself as a modal/status element. VoiceOver users may not know the app is busy or why controls are temporarily blocked.

**Acceptance criteria**
- [ ] Bootstrap `ProgressView` has `.accessibilityLabel("Loading Auralis")` and `.accessibilityValue("Preparing wallet and local data")`
- [ ] Image-generation overlay uses `.accessibilityElement(children: .combine)`, `.accessibilityLabel("Generating images")`, `.accessibilityValue("In progress")`, and `.accessibilityAddTraits(.updatesFrequently)`
- [ ] Background controls are hidden from the accessibility tree while the overlay is active (`.accessibilityHidden(true)` on underlying content or `.accessibilitySortPriority` to bring the overlay to front)
- [ ] An announcement is posted when long-running work completes

**Reference implementation**
```swift
ProgressView("Loading Auralis")
    .accessibilityLabel("Loading Auralis")
    .accessibilityValue("Preparing wallet and local data")

loadingOverlay
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Generating images")
    .accessibilityValue("In progress")
    .accessibilityAddTraits(.updatesFrequently)
    .accessibilitySortPriority(10)
```

---

### A11Y-004 · Add combined labels and actions to `ReceiptTimelineRow`

**Severity:** High  
**Area:** VoiceOver · Lists · Navigation  
**File:** `Auralis/Auralis/Receipts/ReceiptTimelineRow.swift`  
**Lines:** 7–64

**Problem**  
Each row exposes summary, trigger, status, relative date, scope, actor, account, chain, correlation ID, and provenance as separate child elements. Inside a `NavigationLink`, SwiftUI traverses these in a noisy order. Switch Control users cannot copy the correlation ID without opening the detail screen.

**Acceptance criteria**
- [ ] Row (or its `NavigationLink`) uses `.accessibilityElement(children: .ignore)` with a composed label/value
- [ ] Label is `record.summary`; value includes status, trigger, scope, and provenance
- [ ] Hint is `"Shows receipt details"`
- [ ] A custom accessibility action "Copy correlation ID" is added where `record.correlationID` is non-nil

**Reference implementation**
```swift
ReceiptTimelineRow(record: record)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(record.summary)
    .accessibilityValue("\(record.statusTitle). \(record.trigger). \(record.scope). \(record.provenance)")
    .accessibilityHint("Shows receipt details")
    .accessibilityAction(named: "Copy correlation ID") {
        UIPasteboard.general.string = record.correlationID
    }
```

---

### A11Y-005 · Remove unsafe `lineLimit(1)` from music metadata at accessibility sizes

**Severity:** High  
**Area:** Dynamic Type · VoiceOver  
**Files:**
- `MusicFeature/.../Playback/AuraPlayMiniPlayerView.swift` (lines 187–195)
- `MusicFeature/.../Playback/AuraPlayNowPlayingView.swift` (lines 322–343)
- `MusicFeature/.../Playback/AuraPlayRecentlyPlayedSection.swift` (lines 196–210)

**Problem**  
Track title and artist use `.lineLimit(1)` across the mini-player, Now Playing preview rows, and Recently Played. NFT-derived titles are often long. At accessibility text sizes this truncates the exact track being identified or activated.

**Acceptance criteria**
- [ ] All three files read `@Environment(\.dynamicTypeSize)` and increase `lineLimit` to 2–3 at `.isAccessibilitySize`
- [ ] `fixedSize(horizontal: false, vertical: true)` is added alongside the relaxed limit
- [ ] Mini-player layout stacks controls below metadata (VStack) at accessibility sizes instead of HStack
- [ ] No visible layout regression at standard sizes

**Reference implementation**
```swift
@Environment(\.dynamicTypeSize) private var dynamicTypeSize

Text(currentTrack.title ?? "Unknown Title")
    .font(.subheadline.weight(.semibold))
    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
    .fixedSize(horizontal: false, vertical: true)
```

---

### A11Y-006 · Add accessibility values to playback sliders

**Severity:** High  
**Area:** VoiceOver · Media Controls  
**Files:**
- `MusicFeature/.../Playback/AuraPlayMiniPlayerView.swift` (lines 125–136)
- `MusicFeature/.../Playback/AuraPlayNowPlayingView.swift` (lines 53–64)

**Problem**  
Both sliders expose `.accessibilityLabel("Playback position")` but no value. VoiceOver reads a raw percentage. Users need elapsed time and total duration before adjusting playback.

**Acceptance criteria**
- [ ] Both sliders add `.accessibilityValue("\(timeString(from: seekValue)) of \(timeString(from: track.duration))")`
- [ ] Both sliders add `.accessibilityHint("Swipe up or down to seek")`
- [ ] `timeString` helper formats seconds as `m:ss`

**Reference implementation**
```swift
Slider(value: $seekValue, in: 0...max(1, track.duration), ...)
    .accessibilityLabel(String(localized: "Playback position"))
    .accessibilityValue(
        String(localized: "\(timeString(from: seekValue)) of \(timeString(from: track.duration))")
    )
    .accessibilityHint(String(localized: "Swipe up or down to adjust playback position."))
```

---

### A11Y-007 · Disable viewport-height NFT paging at accessibility Dynamic Type sizes

**Severity:** High  
**Area:** Dynamic Type · Navigation · Motor  
**File:** `NFTLibraryFeature/Sources/NFTLibraryFeature/Presentation/NFTLibraryRootViews.swift`  
**Lines:** 138–168

**Problem**  
Each NFT card is forced to `minHeight/maxHeight = geometry.size.height` with paging scroll behavior. At accessibility text sizes, metadata inside a single page becomes cramped or hidden behind a scroll-within-scroll interaction.

**Acceptance criteria**
- [ ] View reads `@Environment(\.dynamicTypeSize)`
- [ ] At `.isAccessibilitySize`, renders a non-paging `LazyVStack` of summary cards instead of the full-screen pager
- [ ] `.scrollTargetBehavior` is only applied at standard sizes
- [ ] Card tap action and VoiceOver label/hint are identical in both layouts

**Reference implementation**
```swift
if dynamicTypeSize.isAccessibilitySize {
    ScrollView {
        LazyVStack(spacing: 16) {
            ForEach(displayNFTs) { nft in
                Button { actions.openNFT(nft.id) } label: {
                    NFTLibraryCardSummaryView(nft: nft)
                }
            }
        }
        .padding()
    }
} else {
    pagedCardScrollView
}
```

---

### A11Y-008 · Announce search query classification to VoiceOver

**Severity:** High  
**Area:** VoiceOver · Forms · Dynamic Content  
**File:** `Auralis/Auralis/Aura/Search/SearchRootView.swift`  
**Lines:** 326–360

**Problem**  
The detection card updates as the query is typed, but no announcement or accessibility value is tied to the query field. VoiceOver users may not know whether their input was classified as a wallet address, contract, ENS name, or plain text without swiping away from the field.

**Acceptance criteria**
- [ ] The search field exposes `.accessibilityValue` containing the query and its current classification (updated after debounce, not every keystroke)
- [ ] A debounced `AuraAccessibilityAnnouncer.announce(...)` fires when classification changes after the user pauses typing
- [ ] Announcement is suppressed when the query field is empty

**Reference implementation**
```swift
.accessibilityValue(
    query.isEmpty ? "Empty" : "\(query). Detected as \(classification.kind.title)"
)
```

---

### A11Y-009 · Centralize icon semantics in `SystemImage` / `AuraIcons`

**Severity:** High  
**Area:** VoiceOver · Images · Design System  
**File:** `AuraUI/Sources/AuraUI/AuraIcons.swift`  
**Lines:** 3–19

**Problem**  
`SystemImage` wraps `Image(systemName:)` without requiring a label or decorative intent. Each of the ~44 call sites must independently remember to add `.accessibilityHidden(true)` or an accessibility label. This is brittle and inconsistently applied.

**Acceptance criteria**
- [ ] `SystemImage` accepts an `AuraImageAccessibility` enum: `.decorative` (default), `.label(LocalizedStringKey)`, `.control(label:, hint:)`
- [ ] `.decorative` automatically applies `.accessibilityHidden(true)`
- [ ] `.label(...)` applies `.accessibilityLabel(...)` and removes the hidden flag
- [ ] Existing call sites are audited; meaningfully interactive ones are migrated to `.label` or `.control`
- [ ] A lint rule or compile-time warning is added for unlabeled icon-only `Button` content

**Reference implementation**
```swift
public enum AuraImageAccessibility {
    case decorative
    case label(LocalizedStringKey)
    case control(label: LocalizedStringKey, hint: LocalizedStringKey? = nil)
}

public struct SystemImage: View {
    private let systemName: String
    private let accessibility: AuraImageAccessibility

    public init(_ systemName: String, accessibility: AuraImageAccessibility = .decorative) {
        self.systemName = systemName
        self.accessibility = accessibility
    }
}
```

---

## Phase 2 — Design System Defaults

### A11Y-010 · Add scaled padding to `AuraActionButton`

**Severity:** Medium  
**Area:** Touch Targets · Dynamic Type  
**File:** `AuraUI/Sources/AuraUI/AuraActions.swift`  
**Lines:** 26–49, 60–74

**Problem**  
Button padding is fixed. At larger Dynamic Type sizes, fixed padding can make the control feel cramped or undermine the minimum touch target.

**Acceptance criteria**
- [ ] Padding uses `@ScaledMetric` relative to `.body`
- [ ] Minimum touch target remains ≥ 44 pt at all text sizes
- [ ] Existing Aura colors, opacity, and border treatment are preserved

**Reference implementation**
```swift
@ScaledMetric(relativeTo: .body) private var horizontalPadding = 16
@ScaledMetric(relativeTo: .body) private var verticalPadding = 8
```

---

### A11Y-011 · Split `AuraPill` into decorative, labeled, and icon-only status variants

**Severity:** Medium  
**Area:** VoiceOver · Status · Design System  
**File:** `AuraUI/Sources/AuraUI/AuraStatus.swift`  
**Lines:** 30–58

**Problem**  
Icon-only pills with no `title` and no explicit accessibility label are silently hidden from VoiceOver rather than communicating status. Status semantics (selected, warning, current) are not centralized.

**Acceptance criteria**
- [ ] Add an `init(systemImage:, emphasis:, accessibilityLabel:)` initializer that requires a label for icon-only usage — the compiler enforces it
- [ ] Add a `decorative` initializer variant that explicitly hides the pill from VoiceOver
- [ ] Document which initializer to use at call sites
- [ ] Existing icon-only usages are audited and migrated

**Reference implementation**
```swift
// Icon-only, meaningful
public init(systemImage: String, emphasis: Emphasis = .neutral, accessibilityLabel: String) { ... }

// Explicitly decorative
public init(systemImage: String, emphasis: Emphasis = .neutral, decorative: Bool) { ... }
```

---

### A11Y-012 · Add non-color cues to warning/error/success messages

**Severity:** Medium  
**Area:** Differentiate Without Color · Design System  
**Files:** `AuraUI/Sources/AuraUI/AuraStatus.swift` (lines 137–149), `AuraUI/Sources/AuraUI/AuraText.swift` (lines 136–159)

**Problem**  
`AuraTrustLabel`, `ErrorText`, and `SuccessText` communicate status primarily through styling. Color-blind users need icon+text+shape structure so status is not dependent on color alone.

**Acceptance criteria**
- [ ] Existing warning/error/success colors are preserved
- [ ] `ErrorText` and `SuccessText` each include an SF Symbol icon so status is not communicated by color alone
- [ ] `AuraTrustLabel` allows `lineLimit(2)` at accessibility sizes (see A11Y-013)
- [ ] Any color-contrast concerns discovered during implementation are recorded under A11Y-026 instead of changing colors in this ticket

**Reference implementation**
```swift
public struct AuraStatusMessage: View {
    public enum Kind { case success, error }
    let kind: Kind
    let message: String

    public var body: some View {
        Label(message, systemImage: kind == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.footnote)
            .accessibilityLabel("\(kind == .error ? "Error" : "Success"): \(message)")
    }
}
```

---

### A11Y-013 · Fix `AuraTrustLabel` truncation at large text sizes

**Severity:** Medium  
**Area:** Dynamic Type · Security Communication  
**File:** `AuraUI/Sources/AuraUI/AuraStatus.swift`  
**Lines:** 133–136

**Problem**  
`AuraTrustLabel` uses `.lineLimit(1)`. The trust label communicates untrusted/provider-backed status; truncating it removes a key non-color cue and leaves only the triangle icon.

**Acceptance criteria**
- [ ] View reads `@Environment(\.dynamicTypeSize)`
- [ ] `lineLimit` is `nil` or `2` at `.isAccessibilitySize`, `1` otherwise
- [ ] `fixedSize(horizontal: false, vertical: true)` is applied

---

### A11Y-014 · Add `AuraAccessibleSummaryCard` modifier to the design system

**Severity:** Medium  
**Area:** VoiceOver Semantics · Design System  
**File:** `AuraUI/Sources/AuraUI/AuraSurfaces.swift`

**Problem**  
`AuraSurfaceCard` is purely visual. Grouping behavior is left to each caller, producing inconsistent VoiceOver output across `ERC20HoldingRow`, `ReceiptTimelineRow`, and home cards.

**Acceptance criteria**
- [ ] A `auraAccessibleSummary(label:value:hint:)` view modifier is added to `AuraUI`
- [ ] It applies `.accessibilityElement(children: .ignore)`, `.accessibilityLabel`, `.accessibilityValue`, and optionally `.accessibilityHint`
- [ ] Existing complex card call sites are migrated to the modifier

**Reference implementation**
```swift
public extension View {
    func auraAccessibleSummary(label: String, value: String? = nil, hint: String? = nil) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value ?? "")
            .accessibilityHint(hint ?? "")
    }
}
```

---

### A11Y-015 · Verify and remove unused `PrimaryTextButton`

**Severity:** Low  
**Area:** Design System Cleanup  
**File:** `AuraUI/Sources/AuraUI/AuraText.swift`  
**Lines:** 226–243

**Problem**  
`PrimaryTextButton` is currently unused. Keeping an unused button primitive with separate sizing behavior creates future design-system drift and makes accessibility hardening look broader than the active app surface actually is.

**Acceptance criteria**
- [ ] Re-run a project-wide search for `PrimaryTextButton` outside this ticket file
- [ ] If there are still no active call sites, remove `PrimaryTextButton` from `AuraText.swift`
- [ ] If active call sites appear before this ticket is implemented, migrate those call sites to `AuraActionButton` instead of hardening `PrimaryTextButton`
- [ ] Build verifies no public API consumers still depend on `PrimaryTextButton`

---

## Phase 3 — Forms and Navigation

### A11Y-016 · Gate gateway scale transition behind Reduce Motion

**Severity:** High  
**Area:** Motion · Animation  
**File:** `AccountsFeature/Sources/AccountsFeature/Presentation/AddressTextField.swift`  
**Lines:** 327–328

**Problem**  
`.transition(.scale.combined(with: .opacity))` fires even when `accessibilityReduceMotion` is true. The view already reads this environment value for other purposes; this transition was missed. Scale transitions can cause vestibular discomfort.

**Acceptance criteria**
- [ ] Transition is `.opacity` when `accessibilityReduceMotion == true`
- [ ] Combined scale+opacity transition is used otherwise (existing behavior)

**Reference implementation**
```swift
.transition(accessibilityReduceMotion ? .opacity : .scale.combined(with: .opacity))
```

---

### A11Y-017 · Add accessibility hint to destructive account-removal button

**Severity:** Medium  
**Area:** VoiceOver · Destructive Actions  
**File:** `AccountsFeature/Sources/AccountsFeature/Presentation/AddressTextField.swift`  
**Lines:** 1247–1255

**Problem**  
The button label correctly identifies the action but does not tell VoiceOver users that a confirmation step follows before the account is deleted.

**Acceptance criteria**
- [ ] `.accessibilityHint("Asks for confirmation before removing this saved account from the device.")` is added to the button

---

### A11Y-018 · Add semantic button to scanner simulator fallback

**Severity:** Medium  
**Area:** UIKit · Motor · Test Flow  
**File:** `CodeScanner/Sources/CodeScanner/ScannerViewController.swift`  
**Lines:** 60–103

**Problem**  
The simulator fallback uses `touchesBegan` ("Tap anywhere"), which is gesture-only and not accessible to VoiceOver or Switch Control.

**Acceptance criteria**
- [ ] A `UIButton` titled "Use simulated code" with an accessibility hint is added to the simulator overlay
- [ ] The button triggers the same scan-result callback as the existing gesture
- [ ] "Tap anywhere" label is either retained as secondary text or removed

---

### A11Y-019 · Announce search history deletion/clear to VoiceOver

**Severity:** Medium  
**Area:** VoiceOver · Forms  
**File:** `Auralis/Auralis/Aura/Search/SearchRootView.swift`  
**Lines:** 470–510

**Problem**  
When a recent search is deleted or all history is cleared, the list changes silently. VoiceOver users need confirmation that the action completed.

**Acceptance criteria**
- [ ] `AuraAccessibilityAnnouncer.announce("Search deleted")` fires after a single-row delete
- [ ] `AuraAccessibilityAnnouncer.announce("Search history cleared")` fires after Clear All
- [ ] Announcements use `String(localized:)`

---

### A11Y-020 · Fix local storage warning banner to expose message in accessibility value

**Severity:** Low  
**Area:** VoiceOver · Errors  
**File:** `Auralis/Auralis/Aura/MainAuraView.swift`  
**Lines:** 72–88

**Problem**  
The banner button label is "Limited local storage warning" but the detailed message inside the banner may not be read as part of the button depending on SwiftUI traversal.

**Acceptance criteria**
- [ ] `.accessibilityValue(primaryStoreInitializationErrorMessage)` is added to the banner button
- [ ] Hint says "Dismisses the local storage warning"

---

### A11Y-021 · Extend `AuraAccessibilityAnnouncer` with focus-change and screen-changed APIs

**Severity:** Medium  
**Area:** Forms · Errors · Announcements  
**File:** `AuraUI/Sources/AuraUI/AuraAccessibilityAnnouncer.swift`

**Problem**  
The announcer currently posts only `.announcement` notifications via `UIAccessibility`. It does not support `.screenChanged` (with focus target) or `.layoutChanged`, and does not use the iOS 17+ `AccessibilityNotification` API where available.

**Acceptance criteria**
- [ ] Add `AuraAccessibilityAnnouncer.screenChanged(_ focusTarget: Any?)` and `layoutChanged(_ focusTarget: Any?)` methods
- [ ] iOS 17+ paths use `AccessibilityNotification.Announcement`, `.ScreenChanged`, and `.LayoutChanged`; iOS 16 uses `UIAccessibility.post`
- [ ] Validation failure in `AddressTextField` calls `screenChanged` with the field as the focus target when a new error appears

---

### A11Y-022 · Standardize NFT copy action naming across menu and VoiceOver custom action

**Severity:** Medium  
**Area:** VoiceOver · Voice Control  
**Files:** `NFTLibraryFeature/.../NFTLibraryRootViews.swift` (lines 157–162), `NFTLibraryFeature/.../NFTLibraryCardView.swift` (lines 141–153)

**Problem**  
The visible menu item says "Copy ID", the VoiceOver custom action says "Copy token ID", and the menu button says "More actions". Voice Control users see "Copy ID" on screen but the custom action does not match.

**Acceptance criteria**
- [ ] Menu item and custom action both use "Copy token ID"
- [ ] The menu `Button` or card `Button` adds `.accessibilityInputLabels(["More actions", "Copy token ID"])`

---

### A11Y-023 · Fix `NewPlaylistView` unlabeled controls and form validation

**Severity:** High  
**Area:** VoiceOver · Voice Control · Forms  
**File:** `Auralis/Auralis/MusicApp/AI/Audio Engine/Playlist/NewPlaylistView.swift`  
**Lines:** 58–70, 93–100, 124–138, 128–133, 254–258

**Problem**  
Three distinct issues in one view:
1. Cover placeholder button (lines 58–70) labels the shape state, not the action.
2. Image Playground sparkles button (lines 93–100) is icon-only with no label.
3. Playlist title validation error (lines 128–133) is not announced and focus is not directed to the failing field; `TextEditor` (lines 136–138) is not wired to its `@FocusState`.

**Acceptance criteria**
- [ ] Cover button: label is "Choose playlist cover", value is "No cover selected", hint is "Opens cover source options"
- [ ] Sparkles button: label is "Generate cover art", hint is "Opens Image Playground for this playlist cover", input labels include "Create cover"
- [ ] Validation: `@FocusState` with `PlaylistField` enum wired to both `TextField` and `TextEditor`; `AuraAccessibilityAnnouncer.announce(message)` fires on validation failure; focus is set to `.title` on failure
- [ ] All strings use `String(localized:)`

---

### A11Y-024 · Apply Reduce Transparency fallback to local `.ultraThinMaterial` backgrounds

**Severity:** Medium  
**Area:** Display Settings · Visual Accessibility  
**Files:** `Auralis/Auralis/MusicApp/AI/Audio Engine/Playlist/NewPlaylistView.swift` (lines 141–146), `MusicFeature/.../Playback/AuraPlayRecentlyPlayedSection.swift` (line 47)

**Problem**  
Both views use `.background(.ultraThinMaterial)` directly, bypassing the Reduce Transparency fallback already built into `AuraSurfaceGlass` / `AuraSurfaceCard`.

**Acceptance criteria**
- [ ] Both backgrounds read `@Environment(\.accessibilityReduceTransparency)`
- [ ] When Reduce Transparency is active, the material falls back to an opaque surface using existing Aura colors
- [ ] Alternatively, both are refactored to use `AuraSurfaceCard` without changing the color palette
- [ ] Any Increase Contrast or color-token concerns are recorded under A11Y-026 instead of changing colors in this ticket

**Reference implementation**
```swift
private var overlayBackground: some ShapeStyle {
    reduceTransparency
    ? AnyShapeStyle(Color.surface)
    : AnyShapeStyle(.ultraThinMaterial)
}
```

---

### A11Y-025 · Gate `GuestPassCard` shimmer overlay behind Reduce Motion and Reduce Transparency

**Severity:** Medium  
**Area:** Motion · Display Settings  
**File:** `AccountsFeature/Sources/AccountsFeature/Presentation/GuestPassCard.swift`  
**Lines:** 49–58, 135–174

**Problem**  
The shimmer animation is correctly gated on `accessibilityReduceMotion`, but the decorative overlay itself renders regardless of `accessibilityReduceTransparency`. An empty string hint on the card when `onTap == nil` can behave inconsistently.

**Acceptance criteria**
- [ ] Animated border overlay is conditionally rendered only when `!reduceMotion && !reduceTransparency`
- [ ] Empty hint (line 47) is replaced: hint is applied only when `onTap != nil`
- [ ] Existing Aura colors are preserved

**Reference implementation**
```swift
if !accessibilityReduceMotion && !reduceTransparency {
    animatedBorderOverlay
}

// Hint only when interactive
if onTap != nil {
    content.accessibilityHint(String(localized: "Opens Auralis with this guest pass account."))
}
```

---

## Phase 4 — Visual Accessibility

### A11Y-026 · Audit existing Aura colors in Accessibility Inspector

**Severity:** Medium  
**Area:** Color Contrast  
**Scope:** Project-wide audit only

**Problem**  
Static analysis cannot measure contrast ratios, and the accessibility plan should not change Aura colors incidentally while fixing unrelated VoiceOver, Dynamic Type, motion, or input issues. Color accessibility needs its own explicit audit and decision path.

**Acceptance criteria**
- [ ] Accessibility Inspector contrast audit run on key surfaces: gateway, home, search, gas, receipts, Now Playing, NFT card
- [ ] Existing Aura colors are measured as-is in Light, Dark, and Increase Contrast settings
- [ ] Results are recorded with screenshots or notes identifying each failing text/background pair and its location
- [ ] No color token, palette, foreground, background, border, opacity, or asset-catalog value is changed as part of this ticket
- [ ] Any required color changes are filed as separate follow-up tickets with product/design approval
- [ ] `AccessibilityAuditUITests` contrast suppression (lines 81–83) is reviewed; a non-blocking log artifact is added for any remaining suppressed failures

---

### A11Y-027 · Hide decorative empty-state icons from VoiceOver

**Severity:** Medium  
**Area:** Images · Empty States  
**Files:** `Auralis/Auralis/Aura/Home/GalleryGrid.swift` (lines 49–58), `MusicFeature` Now Playing empty state

**Problem**  
`photo.on.rectangle` and music note empty-state icons are decorative but not hidden, causing VoiceOver to announce implementation-flavored symbol names before the useful text.

**Acceptance criteria**
- [ ] Both icons have `.accessibilityHidden(true)`
- [ ] Empty-state descriptive text has `.accessibilityAddTraits(.isHeader)` where appropriate

---

### A11Y-028 · Use `@ScaledMetric` for fixed artwork and thumbnail dimensions

**Severity:** Low  
**Area:** Dynamic Type · Layout  
**Files:** `Auralis/Auralis/Aura/Home/GalleryGrid.swift` (lines 62–77), `MusicFeature/.../Library/AuraPlayMusicItemDetailView.swift` (line 160), `MusicFeature/.../Playback/AuraPlayRecentlyPlayedSection.swift` (lines 60, 167, 173)

**Problem**  
Fixed image/card dimensions cause surrounding text to clip at large text sizes rather than the layout adapting.

**Acceptance criteria**
- [ ] Thumbnail/artwork sizes that sit beside text use `@ScaledMetric(relativeTo: .body)`
- [ ] Purely decorative background images may remain fixed
- [ ] Layout branches to stacked VStack at `.isAccessibilitySize` where needed

---

## Phase 5 — Accessibility Testing

### A11Y-029 · Add accessibility preview variants for Increase Contrast, Reduce Motion, and Reduce Transparency

**Severity:** Low  
**Area:** Testing · Previews  
**Files:** `AuraUI/Sources/AuraUI/AuraAccessibilityPreviews.swift`, `Auralis/Auralis/Aura/MainTabView.swift`

**Problem**  
Existing preview matrices cover Accessibility5 and Dark Mode. Increase Contrast, Reduce Motion, Reduce Transparency, and Light Mode with Increased Contrast are not covered, missing a class of visual regressions.

**Acceptance criteria**
- [ ] Preview variants added for gateway, home, search, music (Now Playing), and gas views in: Increased Contrast, Reduce Transparency, Reduce Motion (combined), Light + Increased Contrast
- [ ] Existing large-text and dark-mode previews are retained

**Reference implementation**
```swift
#Preview("Gateway High Contrast Large Text") {
    AccountsGatewayView(dependencies: .preview, onAccountActivated: { _, _ in })
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.colorSchemeContrast, .increased)
}

#Preview("Home Reduce Transparency") {
    MainTabPreviewWrapper(initialTab: .home)
        .environment(\.accessibilityReduceTransparency, true)
        .modelContainer(PreviewModelContainers.primary())
}
```

---

### A11Y-030 · Expand `AccessibilityAuditUITests` to cover modals, validation, and destructive flows

**Severity:** Low  
**Area:** Testing  
**File:** `AuralisUITests/AccessibilityAuditUITests.swift`  
**Lines:** 9–54, 71–87

**Problem**  
Tests cover major tab landing screens only. Sheets, validation errors, active playback, search history, NFT action menus, and destructive confirmations are untested by `performAccessibilityAudit`.

**Acceptance criteria**
- [ ] New test cases added for: account switcher sheet, gateway validation error state, settings reset confirmation, Now Playing sheet, NFT action menu, populated search history, receipt detail, external link confirmation
- [ ] At least one test launches with large accessibility text size via launch arguments
- [ ] Existing tab tests are unchanged

**Reference implementation**
```swift
func testSettingsResetConfirmationAccessibilityAudit() throws {
    let app = launchApp()
    try selectTab("Profile", in: app)
    app.buttons["Settings"].tap()
    app.buttons["Clear Local Privacy Data"].tap()
    try performAudit(in: app)
}

func testSearchValidationStateAccessibilityAudit() throws {
    let app = launchApp()
    try selectTab("Search", in: app)
    let field = app.textFields["search.queryField"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("vitalik.eth")
    try performAudit(in: app)
}
```

---

### A11Y-031 · Localize all accessibility strings project-wide

**Severity:** Low  
**Area:** VoiceOver · Localization  
**Files:** `Auralis/Auralis/Aura/Search/SearchRootView.swift` (lines 317–320, 426–430, 493–510), `Auralis/Auralis/Gas/GasFeeEstimate.swift` (lines 404–406, 642–651, 710–758), `AccountsFeature/.../AddressTextField.swift`, `MusicFeature/.../Playback/*.swift`

**Problem**  
Some accessibility labels, values, and hints are plain string literals while nearby visible copy uses `String(localized:)`. Accessibility strings are user-facing copy and must follow the same localization conventions.

**Acceptance criteria**
- [ ] All `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityHint`, `.accessibilityInputLabels`, and `AuraAccessibilityAnnouncer.announce` call sites use `String(localized:)`
- [ ] A SwiftLint rule or manual grep step is added to the pre-ship checklist to catch bare string literals in accessibility modifiers

---

## Ticket Summary

| ID | Phase | Severity | Title |
|---|---|---|---|
| A11Y-001 | 1 | Critical | Associate validation state with `AddressTextField` |
| A11Y-003 | 1 | Critical | Label and announce bootstrap and overlay loading states |
| A11Y-004 | 1 | High | Add combined labels and actions to `ReceiptTimelineRow` |
| A11Y-005 | 1 | High | Remove unsafe `lineLimit(1)` from music metadata at accessibility sizes |
| A11Y-006 | 1 | High | Add accessibility values to playback sliders |
| A11Y-007 | 1 | High | Disable viewport-height NFT paging at accessibility Dynamic Type sizes |
| A11Y-008 | 1 | High | Announce search query classification to VoiceOver |
| A11Y-009 | 1 | High | Centralize icon semantics in `SystemImage` / `AuraIcons` |
| A11Y-010 | 2 | Medium | Add scaled padding to `AuraActionButton` |
| A11Y-011 | 2 | Medium | Split `AuraPill` into decorative, labeled, and icon-only status variants |
| A11Y-012 | 2 | Medium | Add non-color cues to warning/error/success messages |
| A11Y-013 | 2 | Medium | Fix `AuraTrustLabel` truncation at large text sizes |
| A11Y-014 | 2 | Medium | Add `AuraAccessibleSummaryCard` modifier to the design system |
| A11Y-015 | 2 | Low | Verify and remove unused `PrimaryTextButton` |
| A11Y-016 | 3 | High | Gate gateway scale transition behind Reduce Motion |
| A11Y-017 | 3 | Medium | Add accessibility hint to destructive account-removal button |
| A11Y-018 | 3 | Medium | Add semantic button to scanner simulator fallback |
| A11Y-019 | 3 | Medium | Announce search history deletion/clear to VoiceOver |
| A11Y-020 | 3 | Low | Fix local storage warning banner accessibility value |
| A11Y-021 | 3 | Medium | Extend `AuraAccessibilityAnnouncer` with focus-change APIs |
| A11Y-022 | 3 | Medium | Standardize NFT copy action naming across menu and custom action |
| A11Y-023 | 3 | High | Fix `NewPlaylistView` unlabeled controls and form validation |
| A11Y-024 | 3 | Medium | Apply Reduce Transparency fallback to local `.ultraThinMaterial` backgrounds |
| A11Y-025 | 3 | Medium | Gate `GuestPassCard` shimmer behind Reduce Motion and Reduce Transparency |
| A11Y-026 | 4 | Medium | Audit existing Aura colors in Accessibility Inspector |
| A11Y-027 | 4 | Medium | Hide decorative empty-state icons from VoiceOver |
| A11Y-028 | 4 | Low | Use `@ScaledMetric` for fixed artwork and thumbnail dimensions |
| A11Y-029 | 5 | Low | Add accessibility preview variants for Increase Contrast / Reduce Motion / Reduce Transparency |
| A11Y-030 | 5 | Low | Expand `AccessibilityAuditUITests` to cover modals, validation, and destructive flows |
| A11Y-031 | 5 | Low | Localize all accessibility strings project-wide |
