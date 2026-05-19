import Foundation
import Testing

@Suite
struct ArchitectureBoundaryTests {
    @Test("app target direct package imports are declared explicitly in Xcode")
    func appDirectPackageImportsAreDeclaredExplicitly() throws {
        let projectRoot = try projectRootURL()
        let declaredProducts = try appTargetPackageProductNames(projectRoot: projectRoot)
        let declaredImportModules = declaredProducts.union(modulesExposedByDeclaredProducts(declaredProducts))
        let knownPackageProducts = try knownPackageProductNames(projectRoot: projectRoot)
        let directPackageImports = try appDirectImports(projectRoot: projectRoot)
            .intersection(knownPackageProducts)
        let undeclaredImports = directPackageImports.subtracting(declaredImportModules)

        #expect(
            undeclaredImports.isEmpty,
            "Direct app package imports must be explicit app target package dependencies: \(undeclaredImports.sorted())"
        )
    }

    @Test("NFTKit depends on ReceiptsCore and never ReceiptStorage")
    func nftKitDoesNotDependOnReceiptStorage() throws {
        let projectRoot = try projectRootURL()
        let packageFile = projectRoot
            .appending(path: "NFTKit")
            .appending(path: "Package.swift")
        let packageText = try String(contentsOf: packageFile, encoding: .utf8)
        let sourceImports = try swiftImports(
            under: projectRoot
                .appending(path: "NFTKit")
                .appending(path: "Sources")
        )

        #expect(packageText.contains("../ReceiptsCore"))
        #expect(packageText.contains("../ReceiptStorage") == false)
        #expect(sourceImports.contains("ReceiptsCore"))
        #expect(sourceImports.contains("ReceiptStorage") == false)
    }

    @Test("TokenStorage does not depend on NFTKit")
    func tokenStorageDoesNotDependOnNFTKit() throws {
        let projectRoot = try projectRootURL()
        let packageFile = projectRoot
            .appending(path: "TokenStorage")
            .appending(path: "Package.swift")
        let packageText = try String(contentsOf: packageFile, encoding: .utf8)
        let sourceImports = try swiftImports(
            under: projectRoot
                .appending(path: "TokenStorage")
                .appending(path: "Sources")
        )

        #expect(packageText.contains("../NFTKit") == false)
        #expect(sourceImports.contains("NFTKit") == false)
    }

    @Test("first-party Ethereum address validation uses AuralisPrimaryModels EthereumAddress")
    func firstPartyEthereumAddressValidationUsesPrimaryModel() throws {
        let projectRoot = try projectRootURL()
        let forbiddenPatterns = [
            "^0x[" + "a-fA-F0-9" + "]{40}$",
            "^[" + "a-fA-F0-9" + "]{40}$",
            "^0x[" + "a-f0-9" + "]{40}$",
            "^[" + "a-f0-9" + "]{40}$",
            "^0x[" + "0-9a-fA-F" + "]{40}$"
        ]
        let allowedPathSuffixes: Set<String> = [
            "/web3.swift/web3swift/src/Extensions/String+Numeric.swift"
        ]
        var offenders: [String] = []

        for fileURL in try swiftSourceFiles(under: projectRoot) {
            let path = fileURL.path()
            guard !allowedPathSuffixes.contains(where: { path.hasSuffix($0) }) else {
                continue
            }

            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if forbiddenPatterns.contains(where: { source.contains($0) }) {
                offenders.append(path.replacingOccurrences(of: projectRoot.path() + "/", with: ""))
            }
        }

        #expect(
            offenders.isEmpty,
            "Ethereum address parsing must use AuralisPrimaryModels.EthereumAddress instead of local regexes: \(offenders.sorted())"
        )
    }

    @Test("AppServices delegates feature construction to assemblies")
    func appServicesDelegatesFeatureConstructionToAssemblies() throws {
        let projectRoot = try projectRootURL()
        let appServicesFile = projectRoot
            .appending(path: "Auralis")
            .appending(path: "AppServices.swift")
        let source = try String(contentsOf: appServicesFile, encoding: .utf8)
        let forbiddenConstructionTokens = [
            "NFTService(",
            "AudioEngine(",
            "AuraPlayModelContainer.make",
            "SwiftDataAccountStore(",
            "ReceiptStores.live",
            "SwiftDataTokenHoldingsStore(",
            "LiveERC20HoldingsSyncUseCase(",
            "PrivacyResetServices.live",
            "PolicyActionGateService("
        ]
        let offenders = forbiddenConstructionTokens.filter { source.contains($0) }

        #expect(
            offenders.isEmpty,
            "AppServices.swift should stay a thin composition aggregate; feature construction belongs in assemblies: \(offenders)"
        )
    }

    @Test("assemblies do not keep temporary static live pass-throughs")
    func assembliesDoNotKeepTemporaryStaticLivePassThroughs() throws {
        let projectRoot = try projectRootURL()
        let assembliesRoot = projectRoot
            .appending(path: "Auralis")
            .appending(path: "Assemblies")
        let offenders = try swiftSourceFiles(under: assembliesRoot)
            .filter { fileURL in
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                return source.contains("static func live") || source.contains("static let live")
            }
            .map { $0.path().replacingOccurrences(of: projectRoot.path() + "/", with: "") }

        #expect(
            offenders.isEmpty,
            "Feature assemblies should be injected instance values, not temporary static live pass-throughs: \(offenders.sorted())"
        )
    }

    @Test("shell selection is not persisted with UserDefaults")
    func shellSelectionDoesNotUseUserDefaultsPersistence() throws {
        let projectRoot = try projectRootURL()
        let appSources = projectRoot.appending(path: "Auralis")
        let sourceFiles = try swiftSourceFiles(under: appSources)
        var offenders: [String] = []

        for fileURL in sourceFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains("UserDefaultsShellSelectionPersistence") {
                offenders.append(fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: ""))
            }
        }

        #expect(
            offenders.isEmpty,
            "Shell selection is wallet metadata and must use KeychainShellSelectionPersistence: \(offenders.sorted())"
        )
    }

    @Test("app observable state uses Observation instead of ObservableObject wrappers")
    func appObservableStateUsesObservation() throws {
        let projectRoot = try projectRootURL()
        let appSources = projectRoot.appending(path: "Auralis")
        let forbiddenTokens = [
            "ObservableObject",
            "@Published",
            "@StateObject",
            "@ObservedObject",
            "@EnvironmentObject"
        ]
        var offenders: [String] = []

        for fileURL in try swiftSourceFiles(under: appSources) {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if forbiddenTokens.contains(where: { source.contains($0) }) {
                offenders.append(fileURL.path().replacingOccurrences(of: projectRoot.path() + "/", with: ""))
            }
        }

        #expect(
            offenders.isEmpty,
            "Use @Observable/@State/@Bindable instead of ObservableObject wrappers in app code: \(offenders.sorted())"
        )
    }

    private func appTargetPackageProductNames(projectRoot: URL) throws -> Set<String> {
        let projectFile = projectRoot
            .appending(path: "Auralis.xcodeproj")
            .appending(path: "project.pbxproj")
        let projectText = try String(contentsOf: projectFile, encoding: .utf8)
        let targetBlock = try extractBlock(
            named: "6FB455DA2CC5BEBB009A055C /* Auralis */ =",
            from: projectText
        )
        let dependencyBlock = try extractList(named: "packageProductDependencies", from: targetBlock)
        return Set(commentNames(in: dependencyBlock))
    }

    private func modulesExposedByDeclaredProducts(_ productNames: Set<String>) -> Set<String> {
        var modules = Set<String>()

        if productNames.contains("AuralisPrimaryModels") {
            modules.insert("AuralisPrimaryPersistence")
        }

        return modules
    }

    private func knownPackageProductNames(projectRoot: URL) throws -> Set<String> {
        let packageDirectories = try FileManager.default.contentsOfDirectory(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var productNames = Set<String>()

        for directory in packageDirectories {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { continue }

            let packageFile = directory.appending(path: "Package.swift")
            guard FileManager.default.fileExists(atPath: packageFile.path()) else { continue }

            let packageText = try String(contentsOf: packageFile, encoding: .utf8)
            productNames.formUnion(libraryProductNames(in: packageText))
        }

        productNames.formUnion(["CodeScanner", "web3.swift"])
        return productNames
    }

    private func appDirectImports(projectRoot: URL) throws -> Set<String> {
        try swiftImports(
            under: projectRoot.appending(path: "Auralis"),
            excludingPathComponents: ["/AuralisTests/", "/AuralisUITests/"]
        )
    }

    private func swiftImports(
        under root: URL,
        excludingPathComponents excludedComponents: [String] = []
    ) throws -> Set<String> {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var imports = Set<String>()

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            guard !excludedComponents.contains(where: { fileURL.path().contains($0) }) else { continue }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let source = try String(contentsOf: fileURL, encoding: .utf8)
            imports.formUnion(importedModules(in: source))
        }

        return imports
    }

    private func swiftSourceFiles(under root: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var files: [URL] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            files.append(fileURL)
        }

        return files
    }

    private func importedModules(in source: String) -> Set<String> {
        var modules = Set<String>()

        for line in source.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("import ") else { continue }

            let importTail = trimmed.dropFirst("import ".count)
            let moduleName = importTail.split(whereSeparator: { $0 == " " || $0 == "." }).first
            if let moduleName {
                modules.insert(String(moduleName))
            }
        }

        return modules
    }

    private func libraryProductNames(in packageText: String) -> Set<String> {
        var productNames = Set<String>()
        let pattern = #"\.library\s*\(\s*name:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(packageText.startIndex..<packageText.endIndex, in: packageText)

        for match in regex.matches(in: packageText, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: packageText) else { continue }
            productNames.insert(String(packageText[nameRange]))
        }

        return productNames
    }

    private func extractBlock(named objectName: String, from text: String) throws -> String {
        guard let nameRange = text.range(of: objectName) else {
            Issue.record("Unable to find project object named \(objectName)")
            throw ArchitectureFixtureError()
        }
        guard let blockStart = text[nameRange.upperBound...].firstIndex(of: "{") else {
            Issue.record("Unable to find block start for \(objectName)")
            throw ArchitectureFixtureError()
        }

        return try balancedSubstring(from: blockStart, open: "{", close: "}", in: text)
    }

    private func extractList(named listName: String, from text: String) throws -> String {
        guard let nameRange = text.range(of: listName) else {
            Issue.record("Unable to find list named \(listName)")
            throw ArchitectureFixtureError()
        }
        guard let listStart = text[nameRange.upperBound...].firstIndex(of: "(") else {
            Issue.record("Unable to find list start for \(listName)")
            throw ArchitectureFixtureError()
        }

        return try balancedSubstring(from: listStart, open: "(", close: ")", in: text)
    }

    private func balancedSubstring(
        from start: String.Index,
        open: Character,
        close: Character,
        in text: String
    ) throws -> String {
        var depth = 0
        var current = start

        while current < text.endIndex {
            let character = text[current]
            if character == open {
                depth += 1
            } else if character == close {
                depth -= 1
                if depth == 0 {
                    return String(text[start...current])
                }
            }
            current = text.index(after: current)
        }

        Issue.record("Unable to find balanced substring starting at \(start)")
        throw ArchitectureFixtureError()
    }

    private func commentNames(in text: String) -> [String] {
        var names: [String] = []
        let pattern = #"/\*\s*([^*]+?)\s*\*/"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        for match in regex.matches(in: text, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            names.append(String(text[nameRange]))
        }

        return names
    }

    private func projectRootURL(filePath: String = #filePath) throws -> URL {
        var candidate = URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()

        while candidate.path != "/" {
            let projectPath = candidate.appending(path: "Auralis.xcodeproj").path()
            if FileManager.default.fileExists(atPath: projectPath) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        Issue.record("Unable to locate project root from \(filePath)")
        throw ArchitectureFixtureError()
    }
}

private struct ArchitectureFixtureError: Error {}
