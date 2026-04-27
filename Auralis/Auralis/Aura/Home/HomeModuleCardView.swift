import SwiftUI

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
