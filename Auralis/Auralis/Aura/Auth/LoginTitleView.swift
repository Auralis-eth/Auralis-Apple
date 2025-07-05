//
//  LoginTitleView.swift
//  Auralis
//
//  Created by Daniel Bell on 6/14/25.
//

import SwiftUI

struct LoginTitleView: View {
    var body: some View {
        Text("AURALIS")
            .font(.system(size: 42, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .kerning(2)
    }
}

struct AddressEntryTitleView: View {
    var body: some View {
        HStack {
            Text("Enter Address")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.textPrimary)
            Spacer()
        }
        .padding(.leading, 30)
    }
}
