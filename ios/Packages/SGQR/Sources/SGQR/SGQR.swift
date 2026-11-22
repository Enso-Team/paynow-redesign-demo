import Foundation

public enum ProxyType: String, Sendable, Codable {
    case mobile = "MOBILE"
    case uen = "UEN"
}

public struct PayNowPayload: Equatable, Sendable {
    public var proxyType: ProxyType
    public var proxyValue: String
    public var amount: String?
    public var amountEditable: Bool
    public var expiry: String?
    public var reference: String?
    public var merchantName: String?

    public init(
        proxyType: ProxyType,
        proxyValue: String,
        amount: String? = nil,
        amountEditable: Bool = true,
        expiry: String? = nil,
        reference: String? = nil,
        merchantName: String? = nil
    ) {
        self.proxyType = proxyType
        self.proxyValue = proxyValue
        self.amount = amount
        self.amountEditable = amountEditable
        self.expiry = expiry
        self.reference = reference
        self.merchantName = merchantName
    }
}

public enum SGQRError: Error, Equatable, Sendable, LocalizedError {
    case notPayNow
    case checksumMismatch

    public var errorDescription: String? {
        switch self {
        case .notPayNow: "This QR isn't a PayNow code"
        case .checksumMismatch: "This QR code couldn't be read. Try again."
        }
    }
}

public struct TLV: Equatable, Sendable {
    public let tag: String
    public let value: String
}

public enum SGQR {
    static let payNowGUID = "SG.PAYNOW"

    /// Parses an EMVCo merchant-presented QR and returns its PayNow fields.
    public static func parse(_ raw: String) throws(SGQRError) -> PayNowPayload {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("000201"), let fields = try? tlv(text) else { throw .notPayNow }
        guard let crcField = fields.last, crcField.tag == "63", crcField.value.count == 4 else {
            throw .notPayNow
        }
        let signed = String(text.dropLast(4))
        guard crc16(signed) == crcField.value.uppercased() else { throw .checksumMismatch }

        let template = fields.lazy
            .filter { (26...51).contains(Int($0.tag) ?? -1) }
            .compactMap { field -> [String: String]? in
                guard let sub = try? tlv(field.value) else { return nil }
                let map = Dictionary(sub.map { ($0.tag, $0.value) }, uniquingKeysWith: { first, _ in first })
                return map["00"]?.uppercased() == payNowGUID ? map : nil
            }
            .first
        guard let template else { throw .notPayNow }

        let proxyType: ProxyType
        switch template["01"] {
        case "0": proxyType = .mobile
        case "2": proxyType = .uen
        default: throw .notPayNow
        }
        guard let rawValue = template["02"], !rawValue.isEmpty else { throw .notPayNow }
        let value = proxyType == .mobile
            ? normalizeMobile(rawValue)
            : rawValue.trimmingCharacters(in: .whitespaces).uppercased()

        let top = Dictionary(fields.map { ($0.tag, $0.value) }, uniquingKeysWith: { first, _ in first })
        let reference = top["62"].flatMap { try? tlv($0) }?.first { $0.tag == "01" }?.value

        let amount = top["54"].flatMap { $0.isEmpty ? nil : $0 }
        return PayNowPayload(
            proxyType: proxyType,
            proxyValue: value,
            amount: amount,
            amountEditable: amount == nil || template["03"] != "0",
            expiry: template["04"],
            reference: reference,
            merchantName: top["59"]
        )
    }

    /// Drops spaces and dashes, then a leading +65.
    public static func normalizeMobile(_ value: String) -> String {
        let compact = value.filter { $0 != " " && $0 != "-" }
        return compact.hasPrefix("+65") ? String(compact.dropFirst(3)) : compact
    }

    /// A mobile is 8 digits starting with 8 or 9. A UEN is 9 or 10 letters and digits.
    public static func isValidProxy(_ type: ProxyType, _ value: String) -> Bool {
        switch type {
        case .mobile:
            value.count == 8 && value.allSatisfy(\.isASCII) && value.allSatisfy(\.isNumber)
                && (value.first == "8" || value.first == "9")
        case .uen:
            (9...10).contains(value.count) && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
    }

    /// Splits a string of `tag(2) length(2) value` records.
    public static func tlv(_ text: String) throws(SGQRError) -> [TLV] {
        var out: [TLV] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            guard rest.count >= 4,
                  let length = Int(rest.dropFirst(2).prefix(2)),
                  rest.prefix(2).allSatisfy(\.isNumber),
                  rest.count >= 4 + length
            else { throw .notPayNow }
            let tag = String(rest.prefix(2))
            let value = String(rest.dropFirst(4).prefix(length))
            out.append(TLV(tag: tag, value: value))
            rest = rest.dropFirst(4 + length)
        }
        return out
    }

    /// CRC16-CCITT (poly 0x1021, init 0xFFFF) as four uppercase hex digits.
    public static func crc16(_ text: String) -> String {
        var crc: UInt16 = 0xFFFF
        for byte in text.utf8 {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return String(format: "%04X", crc)
    }

    /// Builds a PayNow SGQR string, CRC included.
    public static func encode(_ payload: PayNowPayload) -> String {
        func field(_ tag: String, _ value: String) -> String {
            tag + String(format: "%02d", value.count) + value
        }
        let proxyCode = payload.proxyType == .mobile ? "0" : "2"
        var account = field("00", payNowGUID) + field("01", proxyCode) + field("02", payload.proxyValue)
            + field("03", payload.amountEditable ? "1" : "0")
        if let expiry = payload.expiry { account += field("04", expiry) }

        var body = field("00", "01") + field("01", payload.amount == nil ? "11" : "12")
            + field("26", account) + field("52", "0000") + field("53", "702")
        if let amount = payload.amount { body += field("54", amount) }
        body += field("58", "SG") + field("59", payload.merchantName ?? "NA") + field("60", "Singapore")
        if let reference = payload.reference { body += field("62", field("01", reference)) }
        body += "6304"
        return body + crc16(body)
    }
}
