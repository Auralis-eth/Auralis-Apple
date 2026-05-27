# Auralis Accessibility Tickets

Synthesized from three project-wide accessibility audits. Issues are deduplicated and grouped by the five-phase refactor plan. Severity is the highest rating assigned across all audits.

**Color scope:** This plan preserves the current Aura color palette. Tickets may add labels, values, focus handling, touch targets, Dynamic Type behavior, motion/transparency accommodations, and non-color cues. Color contrast is tracked only by A11Y-026 as an audit-and-ticketing pass; any actual palette, token, foreground, background, border, opacity, or asset-catalog change requires a separate follow-up ticket with product/design approval.

------

## Phase 4 — Visual Accessibility

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

**Progress**
- [x] Gateway validation error state audit added
- [x] Scanner simulator fallback audit added
- [x] Account switcher removal confirmation audit added
- [x] Settings reset confirmation audit added
- [x] Deterministic clean-gateway and authenticated UI-test launch fixtures added
- [ ] Remaining A11Y-030 scope: Now Playing sheet, NFT action menu, populated search history, receipt detail, external link confirmation, and large-text launch argument coverage

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
