import SwiftUI

struct GlobalChromeView: View {
    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    let onOpenAccountSwitcher: () -> Void
    let onOpenContextInspector: () -> Void
    @Environment(\.modeState) private var modeState

    var body: some View {
        AuraSurfaceCard(style: .soft, cornerRadius: 26, padding: 16) {
            HStack {
                accountButton

                Spacer(minLength: 8)

                AuraPill(
                    systemImage: "eye",
                    emphasis: .accent,
                    imageSize: .title3.weight(.semibold),
                    aceessibilityLabel: modeState.mode.rawValue
                )
                .accessibilityHint("Mode badge is provided by global mode state.")
                
                Button(action: onOpenContextInspector) {
                    AuraPill(
                        systemImage: "gyroscope",
                        emphasis: .accent,
                        imageSize: .title3.weight(.semibold),
                        aceessibilityLabel: modeState.mode.rawValue
                    )
                    .accessibilityHidden(true)
                }
                .accessibilityLabel("Context")
                
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var accountButton: some View {
        Button(action: onOpenAccountSwitcher) {
            HStack(alignment: .top, spacing: 10) {
                SystemImage("person.crop.circle")
                    .font(.title3)
                    .accessibilityHidden(true)

                Text(accountTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current account")
        .accessibilityValue(accountTitle)
        .accessibilityHint("Opens the account switcher.")
    }

    private var accountTitle: String {
        if let name = currentAccount?.name, !name.isEmpty {
            return name
        }

        if !currentAddress.isEmpty {
            return currentAddress.displayAddress
        }

        return "No Account"
    }
}

struct ChromeContextInspectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modeState) private var modeState

    let currentAccount: EOAccount?
    let currentAddress: String
    let currentChain: Chain
    let nftService: NFTService
    let contextSource: ContextSource

    var ctx: AppContext {
        contextSource.snapshot()
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section("Mode") {
                    LabeledContent("Current Mode", value: ctx.mode)
                }

                Section("Scope") {
                    LabeledContent("Account", value: ctx.accountDisplay)
                    LabeledContent("Chain", value: ctx.chainDisplay)
                }

                Section("Freshness") {
                    LabeledContent("Refresh State", value: ctx.freshnessLabel)
                }
            }
            .navigationTitle("Context Inspector")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
