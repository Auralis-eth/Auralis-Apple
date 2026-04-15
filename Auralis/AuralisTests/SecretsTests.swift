//
//  SecretsTests.swift
//  AuralisTests
//
//  Created by Daniel Bell on 5/16/25.
//

import Foundation
import Testing
@testable import Auralis

@Suite struct SecretsTests {
    @Test("missing provider keys fail deterministically when the test bundle is not configured")
    func missingProviderKeyThrowsDeterministicError() {
        do {
            _ = try Secrets.apiKey(.alchemy, bundle: Bundle(for: BundleLocatorClass.self))
            Issue.record("Expected missing Alchemy key to throw.")
        } catch let error as Secrets.SecretsError {
            switch error {
            case .providerKeyNotFound(let provider):
                #expect(provider == .alchemy)
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

class BundleLocatorClass {
}
