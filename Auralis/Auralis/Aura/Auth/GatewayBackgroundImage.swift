//
//  GatewayBackgroundImage.swift
//  Auralis
//
//  Created by Daniel Bell on 6/19/25.
//

import SwiftUI

struct GatewayBackgroundImage: View {
    var body: some View {
        Color.clear
            .overlay(
                Image("aurora-1")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            )
    }
}
