//
//  FetchApp.swift
//  Fetch
//
//  Created by Daniel Bell on 6/11/25.
//

import WebKit
import SwiftUI
import SwiftData

@main
struct FetchApp: App {
    var body: some Scene {
        WindowGroup {
            ConnectView()
                .onOpenURL { incomingURL in
                    print("App was opened via URL: \(incomingURL)")
//                    handleIncomingURL(incomingURL)
                }
        }
    }
}

struct ConnectView: View {
    // We recommend adding support for Infura API for read-only RPCs (direct calls) via SDKOptions
    @ObservedObject var metaMaskSDK = MetaMaskSDK.shared
    @State private var showProgressView = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                    Section {
                        Group {

                            HStack {
                                Text("Chain ID")
                                    .bold()
                                Spacer()
                                Text(metaMaskSDK.chainId)
                            }

                            HStack {
                                Text("Account")
                                    .bold()
                                Spacer()
                                Text(metaMaskSDK.account)
                            }
                        }
                    }
                    .onChange(of: metaMaskSDK.urlToOpen) {
                        if let urlToOpen = metaMaskSDK.urlToOpen {
                            openURL(urlToOpen)
                        }
                    }



                    VStack(spacing: 20) {
                        // Header Section
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Sign-In with Ethereum")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Authenticate using your Ethereum wallet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Connection Status
                        HStack {
                            Circle()
                                .fill(metaMaskSDK.connected ? .green : .red)
                                .frame(width: 8, height: 8)
                            Text(metaMaskSDK.connected ? "Connected" : "Disconnected")
                                .font(.caption)
                        }
                        .padding(.horizontal)

                        // Connect Button
                        if !metaMaskSDK.connected {
                            ZStack {
                                Button {
                                    Task {
                                        showProgressView = true
                                        await metaMaskSDK.connect()
                                        showProgressView = false

                                    }
                                } label: {
                                    Text("Connect to MetaMask")
                                        .frame(maxWidth: .infinity, maxHeight: 44)
                                }

                                if showProgressView {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                            }
                        }
                    }
                    .padding()

                    Button {
                        metaMaskSDK.clearSession()
                    } label: {
                        Text("Clear Session")
                            .frame(maxWidth: .infinity, maxHeight: 32)
                    }

                }
            }
            .font(.body)
            .navigationTitle("Dub Dapp")
        }
    }
}

