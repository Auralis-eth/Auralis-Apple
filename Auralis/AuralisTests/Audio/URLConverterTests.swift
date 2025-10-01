//import Foundation
//import Testing
//@testable import Auralis
//
//@Suite("URLConverter conversion matrix")
//struct URLConverterTests {
//    private func expectSuccess(_ result: Result<String, URLConversionError>, equals expected: String, file: StaticString = #fileID, line: UInt = #line) {
//        switch result {
//        case .success(let value):
//            #expect(value == expected, "Expected success=\(expected), got=\(value)")
//        case .failure(let error):
//            #expect(false, "Expected success but got error: \(error)", sourceLocation: SourceLocation(fileID: file, line: line))
//        }
//    }
//
//    private func expectFailure(_ result: Result<String, URLConversionError>, is expected: URLConversionError, file: StaticString = #fileID, line: UInt = #line) {
//        switch result {
//        case .success(let value):
//            #expect(false, "Expected failure=\(expected) but got success: \(value)", sourceLocation: SourceLocation(fileID: file, line: line))
//        case .failure(let error):
//            #expect("\(error)" == "\(expected)", "Expected error=\(expected), got=\(error)")
//        }
//    }
//
//    @Test("ipfs:// hash converts to preferred HTTPS gateway")
//    func testIPFSContentToPreferred() {
//        let input = "ipfs://QmHash/path/to/file"
//        let result = URLConverter.convertToPreferredHTTPS(input)
//        // Expect optimizedLocation if configured; fallback to location otherwise.
//        // Based on URIConfig in code, optimizedLocation is https://alchemy.mypinata.cloud/ipfs/
//        expectSuccess(result, equals: "https://alchemy.mypinata.cloud/ipfs/QmHash/path/to/file")
//    }
//
//    @Test("https ipfs location upgrades to preferred optimized gateway when available")
//    func testIPFSLocationUpgrade() {
//        let input = "https://ipfs.io/ipfs/QmHash/asset.mp3"
//        let result = URLConverter.convertToPreferredHTTPS(input)
//        expectSuccess(result, equals: "https://alchemy.mypinata.cloud/ipfs/QmHash/asset.mp3")
//    }
//
//    @Test("ar:// with valid transaction ID converts; invalid fails")
//    func testArweaveValidation() {
//        // 43-char base64url-ish id
//        let validID = String(repeating: "a", count: 43)
//        let ok = URLConverter.convertToPreferredHTTPS("ar://\(validID)/meta.json")
//        expectSuccess(ok, equals: "https://arweave.net/\(validID)/meta.json")
//
//        // invalid id (too short)
//        let bad = URLConverter.convertToPreferredHTTPS("ar://short/meta.json")
//        expectFailure(bad, is: .invalidIdentifier)
//    }
//
//    @Test("http is upgraded to https")
//    func testHTTPToHTTPS() {
//        let input = "http://example.com/file.mp3"
//        let result = URLConverter.convertToPreferredHTTPS(input)
//        expectSuccess(result, equals: "https://example.com/file.mp3")
//    }
//
//    @Test("unsupported schemes and empty strings fail")
//    func testUnsupportedAndEmpty() {
//        let empty = URLConverter.convertToPreferredHTTPS("")
//        expectFailure(empty, is: .emptyString)
//
//        let ftp = URLConverter.convertToPreferredHTTPS("ftp://example.com/file")
//        expectFailure(ftp, is: .unsupportedScheme)
//    }
//
//    @Test("https passthrough remains unchanged")
//    func testHTTPSPassthrough() {
//        let input = "https://example.com/same"
//        let result = URLConverter.convertToPreferredHTTPS(input)
//        expectSuccess(result, equals: input)
//    }
//}
