//
//  EnergyCardView.swift
//  Auralis
//
//  Created by Daniel Bell on 2/21/26.
//

import SwiftUI

struct EnergyCardView: View {
    // MARK: - Config
    let title: String = "Energy"
    var time: Date = {
        var comps = DateComponents()
        comps.hour = 9
        comps.minute = 30
        // Fallback to now if Calendar fails to build the date
        return Calendar.current.date(from: comps) ?? Date()
    }()
    var statusTitle: String = "Warming up"
    var statusSubtitle: String = "Morning energy"
    var symbolName: String = "sun.max.fill"

    // MARK: - Formatting
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "hh:mm a"
        return formatter.string(from: time)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            SubheadlineFontText(title)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Content
            HStack(alignment: .center) {
                // Left: Time
                Title2FontText(timeString)

                Spacer()

                // Right: Status + Icon
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 4) {
                        PrimaryText(statusTitle)
                            .font(.headline)
                            .fontWeight(.semibold)
                        SecondaryText(statusSubtitle)
                            .font(.footnote)
                    }

                    SystemImage(symbolName)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.yellow, .orange)
                        .font(.system(size: 34, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(20)
    }
}
#Preview("Energy Card") {
    VStack(spacing: 20) {
        EnergyCardView()
        EnergyCardView(
            time: Calendar.current.date(bySettingHour: 6, minute: 45, second: 0, of: Date()) ?? Date(),
            statusTitle: "Peak Focus",
            statusSubtitle: "Daytime energy",
            symbolName: "sunrise.fill"
        )
    }
    .padding()
    .preferredColorScheme(.dark)
}

