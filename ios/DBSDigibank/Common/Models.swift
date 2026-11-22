import Foundation
import SGQR

/// What the PayNow form opens with (`window.__PAYNOW_INIT__`).
struct PaynowInit: Codable, Hashable, Sendable {
    var proxyType: String?
    var proxyValue: String?
    var amount: String?
    var amountEditable: Bool
    var reference: String?
    var source: String

    static func menu(_ type: ProxyType) -> PaynowInit {
        PaynowInit(proxyType: type.rawValue, amountEditable: true, source: "menu")
    }

    init(proxyType: String? = nil, proxyValue: String? = nil, amount: String? = nil,
         amountEditable: Bool, reference: String? = nil, source: String) {
        self.proxyType = proxyType
        self.proxyValue = proxyValue
        self.amount = amount
        self.amountEditable = amountEditable
        self.reference = reference
        self.source = source
    }

    init(qr payload: PayNowPayload) {
        self.init(
            proxyType: payload.proxyType.rawValue,
            proxyValue: payload.proxyValue,
            amount: payload.amount,
            amountEditable: payload.amountEditable,
            reference: payload.reference,
            source: "qr"
        )
    }
}

/// What the form hands back through `paynowHost.done`.
struct PaymentResult: Codable, Hashable, Sendable {
    var paymentId: String
    var status: String
    var amount: String
    var maskedName: String

    var settled: Bool { status == "SETTLED" }
}

struct AccountsSummary: Codable, Sendable, Equatable {
    struct Account: Codable, Sendable, Equatable, Identifiable {
        var id: String
        var name: String
        var numberMasked: String
        var balance: String
        var available: String
        var currency: String
    }

    var displayName: String
    var accounts: [Account]
    var paynowDailyLimit: String
    var paynowUsedToday: String
    var updatedAt: String?

    var totalAvailable: Decimal {
        accounts.reduce(Decimal.zero) { $0 + (Decimal(string: $1.available) ?? 0) }
    }
}

enum Money {
    static func format(_ value: Decimal) -> String {
        value.formatted(.number.precision(.fractionLength(2)).grouping(.automatic).locale(Locale(identifier: "en_SG")))
    }

    static func format(_ text: String) -> String {
        Decimal(string: text).map(format) ?? text
    }
}
