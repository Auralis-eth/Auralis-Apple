//
//  ConnectionStatusView.swift
//  Auralis
//
//  Created by Daniel Bell on 4/9/25.
//

import SwiftUI

// MARK: - Connection Status View
struct ConnectionStatusView: View {
    let account: String
    let connected: Bool

    var body: some View {
        HStack {
            if !account.isEmpty {
                Text("Connected as \(account)...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if connected {
                    Circle()
                        .fill(Color.success)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding()
        .background(Color.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.deepBlue.opacity(0.2), lineWidth: 1)
        )
    }
}

