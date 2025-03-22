//
//  Untitled.swift
//  Auralis
//
//  Created by Daniel Bell on 12/2/24.
//


import Testing
@testable import Auralis

//@Suite("keychain")
struct KeychainServiceTests {


//    @Test("TEST_NAME")
//    @Test(.bug(id: 420))
//    @Test(.tags(.keychain))
//    @Test(.enabled(false))
//    @Test(.disabled(true))
    @Test func keyChainFunction() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
//        #expect(KeychainService().text == "Hello, World!")
//        try #require(KeychainService().text != "Hello, World!")
//        let service = #require(KeychainService().services.first)
    }
    @Test func keyChainSave() async throws {
        let service = KeychainService()
        let success = try service.save(value: "test", forKey: "test")
        #expect(success)
        #expect(try service.loadData(forKey: "test") == "test")
    }
}

