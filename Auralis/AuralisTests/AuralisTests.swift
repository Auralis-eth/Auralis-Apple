////
////  AuralisTests.swift
////  AuralisTests
////
////  Created by Daniel Bell on 10/20/24.
////
//
//import Testing
//@testable import Auralis
//
//struct AuralisTests {
//    @Test func example() async throws {
//        let abc: Password = ""
//        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
//    }
//
//    @Test func anyValueString() async throws {
//        let abc: Password = ""
//        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
//    }
//
////    @Test("Continents mentioned in videos", arguments: [
////        "A Beach",
////        "By the Lake",
////        "Camping in the Woods"
////    ])
////    func mentionedContinents(videoName: String) async throws {
////        let videoLibrary = try await VideoLibrary()
////        let video = try #require(await videoLibrary.video(named: videoName))
////        #expect(video.mentionedContinents.count <= 3)
////    }
//
////    @Test("Can make large orders", arguments: zip(Food.allCases, 1 ... 100))
////    func makeLargeOrder(of food: Food, count: Int) async throws {
////      let foodTruck = FoodTruck(selling: food)
////      #expect(await foodTruck.cook(food, quantity: count))
////    }
//}
//
////@Suite("Food truck tests") struct FoodTruckTests {
////  @Test func foodTruckExists() { ... }
////}
//
//////@Suite("keychain")
////struct KeychainServiceTests {
////
////
//////    @Test("TEST_NAME")
//////    @Test(.bug(id: 420))
//////    @Test(.tags(.keychain))
//////    @Test(.enabled(false))
//////    @Test(.disabled(true))
////    @Test func keyChainFunction() async throws {
////        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
//////        #expect(KeychainService().text == "Hello, World!")
//////        try #require(KeychainService().text != "Hello, World!")
//////        let service = #require(KeychainService().services.first)
////    }
////    @Test func keyChainSave() async throws {
////        let service = KeychainService()
////        let success = try service.save(value: "test", forKey: "test")
////        #expect(success)
////        #expect(try service.loadData(forKey: "test") == "test")
////    }
////}
////
