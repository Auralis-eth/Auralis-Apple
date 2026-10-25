import AccountsCore

@MainActor
public struct AddressEntryValidationPresentation: Equatable, Sendable {
    public let validationMessage: String?
    public let normalizedAddress: String?

    public init(validationMessage: String?, normalizedAddress: String?) {
        self.validationMessage = validationMessage
        self.normalizedAddress = normalizedAddress
    }

    public static func make(input: String) -> AddressEntryValidationPresentation {
        let validationResult = AccountStore.validateAddressInput(input)
        let isENSInput = AccountStore.looksLikeENSName(input)

        let validationMessage: String?
        if isENSInput {
            validationMessage = nil
        } else {
            switch validationResult {
            case .empty, .valid:
                validationMessage = nil
            case .unsupportedENS, .invalidFormat:
                validationMessage = validationResult.userFacingMessage
            }
        }

        return AddressEntryValidationPresentation(
            validationMessage: validationMessage,
            normalizedAddress: isENSInput ? nil : validationResult.normalizedAddress
        )
    }
}

public struct AccountErrorPresentation: Equatable, Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public struct AccountActivationErrorPresenter: Sendable {
    public init() { }

    public func presentation(for error: any Error) -> AccountErrorPresentation {
        switch error {
        case AccountStoreError.invalidAddress:
            return AccountErrorPresentation(
                title: "Invalid Address",
                message: AccountStoreError.invalidAddress.localizedDescription
            )
        case AccountStoreError.duplicateAddress:
            return AccountErrorPresentation(
                title: "Account Already Added",
                message: "Switched to the existing saved account for that address."
            )
        default:
            return AccountErrorPresentation(
                title: "Save Failed",
                message: "Failed to save account: \(error.localizedDescription)"
            )
        }
    }
}

public struct AccountENSResolutionPresentation: Equatable, Sendable {
    public let resolvedAddress: String?
    public let resolvedName: String?
    public let alert: AccountErrorPresentation?

    public init(
        resolvedAddress: String?,
        resolvedName: String?,
        alert: AccountErrorPresentation?
    ) {
        self.resolvedAddress = resolvedAddress
        self.resolvedName = resolvedName
        self.alert = alert
    }
}

public struct AccountENSResolutionPresenter: Sendable {
    public init() { }

    public func presentation(for resolution: AccountENSResolution) -> AccountENSResolutionPresentation {
        guard !resolution.isStale else {
            return AccountENSResolutionPresentation(
                resolvedAddress: nil,
                resolvedName: nil,
                alert: AccountErrorPresentation(
                    title: "ENS Verification Unavailable",
                    message: "Auralis found only a cached ENS mapping for this name and will not save it until the provider can verify the address live. Try again when connectivity recovers."
                )
            )
        }

        return AccountENSResolutionPresentation(
            resolvedAddress: resolution.address,
            resolvedName: resolution.ensName,
            alert: nil
        )
    }

    public func presentation(for failure: AccountENSResolutionFailure) -> AccountErrorPresentation {
        switch failure {
        case .mappingChanged:
            return AccountErrorPresentation(
                title: "ENS Mapping Changed",
                message: "The ENS mapping changed. Review the resolved address before saving this account."
            )
        case .unavailable:
            return AccountErrorPresentation(
                title: "Save Failed",
                message: "Failed to save account: \(failure.localizedDescription)"
            )
        }
    }
}
