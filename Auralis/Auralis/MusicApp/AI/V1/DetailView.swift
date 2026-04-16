import SwiftUI

struct DetailView: View {
    let item: String

    var body: some View {
        VStack(spacing: 20) {
            SystemImage(iconForItem(item))
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text(item)
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("This is the detail view for \(item)")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()

            Spacer()
        }
        .padding()
        .navigationTitle(item)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func iconForItem(_ item: String) -> String {
        switch item {
        case "Home": return "house.fill"
        case "Profile": return "person.circle.fill"
        case "Settings": return "gear"
        case "About": return "info.circle.fill"
        case "Help": return "questionmark.circle.fill"
        default: return "circle.fill"
        }
    }
}
