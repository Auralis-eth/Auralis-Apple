//
//  SecretsTests.swift
//  AuralisTests
//
//  Created by Daniel Bell on 5/16/25.
//

@testable import Auralis
import Foundation
import Testing
import NFTDomain
import NFTPersistence
import NFTPresentation
import NFTProviderAdapters
import ProviderKit

@Suite struct SecretsTests {
    @Test("missing provider keys fail deterministically when the test bundle is not configured")
    func missingProviderKeyThrowsDeterministicError() throws {
        let error = #expect(throws: Secrets.SecretsError.self) {
            _ = try Secrets.apiKey(.alchemy, bundle: Bundle(for: BundleLocatorClass.self))
        }
        let secretsError = try #require(error)
        guard case .providerKeyNotFound(let provider) = secretsError else {
            Issue.record("Unexpected error type: \(secretsError)")
            return
        }
        #expect(provider == .alchemy)
    }
}

class BundleLocatorClass {
}
