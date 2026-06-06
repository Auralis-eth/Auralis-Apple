import OperatorCore
import ReceiptsCore
@testable import Auralis
import AuralisPrimaryModels
import AuralisTestSupport
import Foundation
import Testing

struct ExternalLinkOpenFlowTests {
    @Test("confirmed open logs first and then opens the destination")
    @MainActor
    func confirmedOpenLogsBeforeOpen() async throws {
        let logger = RecordingExternalLinkEventLogger()
        var openedURLs: [URL] = []
        var sequence: [String] = []

        let flow = ExternalLinkOpenFlow(
            eventLogger: logger,
            openURL: { url in
                sequence.append("open")
                openedURLs.append(url)
            }
        )

        let request = ExternalLinkOpenRequest(
            label: "OpenSea",
            url: try #require(URL(string: "https://opensea.io/assets/base/0xabc/1")),
            surface: "newsfeed.nft_detail"
        )

        logger.onRecord = {
            sequence.append("log")
        }

        let outcome = await flow.confirm(request)

        #expect(sequence == ["log", "open"])
        #expect(logger.requests == [request])
        #expect(openedURLs == [request.url])
        #expect(outcome == .opened)
    }

    @Test("confirmed open preserves explicit provenance for non-user initiators")
    @MainActor
    func confirmedOpenPreservesProvenance() async throws {
        let logger = RecordingExternalLinkEventLogger()
        let flow = ExternalLinkOpenFlow(eventLogger: logger, openURL: { _ in })

        let request = ExternalLinkOpenRequest(
            label: "Plugin",
            url: try #require(URL(string: "https://ipfs.io/ipfs/QmHash")),
            surface: "plugin.runtime",
            provenance: .pluginConfirmed
        )

        let outcome = await flow.confirm(request)

        #expect(try #require(logger.requests.first).provenance == .pluginConfirmed)
        #expect(outcome == .opened)
    }

    @Test("durable confirmed open blocks when receipt logging fails")
    @MainActor
    func durableConfirmedOpenBlocksOnLoggingFailure() async throws {
        let logger = FailingExternalLinkEventLogger()
        var openedURLs: [URL] = []
        let flow = ExternalLinkOpenFlow(
            eventLogger: logger,
            openURL: { url in
                openedURLs.append(url)
            }
        )

        let request = ExternalLinkOpenRequest(
            label: "Explorer",
            url: try #require(URL(string: "https://etherscan.io/token/0xabc?a=1")),
            surface: "newsfeed.nft_detail"
        )

        let outcome = await flow.confirm(request)

        #expect(logger.requests == [request])
        #expect(openedURLs.isEmpty)
        #expect(outcome == .blockedMissingAudit)
    }

    @Test("best-effort confirmed open still opens with warning when receipt logging fails")
    @MainActor
    func bestEffortConfirmedOpenWarnsOnLoggingFailure() async throws {
        let logger = FailingExternalLinkEventLogger()
        var openedURLs: [URL] = []
        let flow = ExternalLinkOpenFlow(
            eventLogger: logger,
            openURL: { url in
                openedURLs.append(url)
            }
        )

        let request = ExternalLinkOpenRequest(
            label: "Docs",
            url: try #require(URL(string: "https://example.com/docs")),
            surface: "settings.help",
            auditRequirement: .bestEffort
        )

        let outcome = await flow.confirm(request)

        #expect(logger.requests == [request])
        #expect(openedURLs == [request.url])
        #expect(outcome == .openedWithAuditWarning)
    }
}

@MainActor
private final class RecordingExternalLinkEventLogger: ExternalLinkEventLogging {
    var requests: [ExternalLinkOpenRequest] = []
    var onRecord: (() -> Void)?

    func recordConfirmedOpen(_ request: ExternalLinkOpenRequest) async throws -> ReceiptRecord {
        requests.append(request)
        onRecord?()
        return ReceiptRecord(
            id: UUID(),
            sequenceID: requests.count,
            createdAt: Fixture.referenceDate,
            actor: request.provenance.receiptActor,
            mode: .observe,
            trigger: "external_link.opened",
            scope: "navigation.external",
            summary: "Opened external link",
            provenance: request.provenance.rawValue,
            isSuccess: true,
            correlationID: nil,
            details: ReceiptPayload(values: [:])
        )
    }
}

@MainActor
private final class FailingExternalLinkEventLogger: ExternalLinkEventLogging {
    enum LoggerError: Error {
        case writeFailed
    }

    var requests: [ExternalLinkOpenRequest] = []

    func recordConfirmedOpen(_ request: ExternalLinkOpenRequest) async throws -> ReceiptRecord {
        requests.append(request)
        throw LoggerError.writeFailed
    }
}
