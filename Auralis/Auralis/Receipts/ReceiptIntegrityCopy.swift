enum ReceiptIntegrityCopy {
    static let timelineNotice = "Receipts are hash-chained and checked against a Keychain-protected head on this device. They provide local tamper evidence, not third-party proof."

    static let detailValue = "Local tamper evidence. Verification checks this device's hash chain and protected head; production-grade external proof requires trusted infrastructure or signed receipt-head sync."
}
