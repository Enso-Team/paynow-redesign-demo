import Testing
@testable import SGQR

/// Mirrors `web/app/packages/sgqr/src/index.test.ts` so both parsers agree.
@Suite("SGQR")
struct SGQRTests {
    func field(_ tag: String, _ value: String) -> String { tag + String(format: "%02d", value.count) + value }

    @Test func crcMatchesTheCCITTFalseCheckValue() {
        #expect(SGQR.crc16("123456789") == "29B1")
        #expect(SGQR.crc16("") == "FFFF")
    }

    @Test func splitsTags() throws {
        #expect(try SGQR.tlv("000201010211") == [TLV(tag: "00", value: "01"), TLV(tag: "01", value: "11")])
        #expect(throws: SGQRError.notPayNow) { try SGQR.tlv("0005abc") }
    }

    @Test func readsTheMobileSampleAndStripsPlus65() throws {
        let qr = try SGQR.parse(SGQRSample.mobile.raw)
        #expect(qr.proxyType == .mobile)
        #expect(qr.proxyValue == "91234567")
        #expect(qr.amount == "12.50")
        #expect(qr.amountEditable == false)
        #expect(qr.expiry == "20301231")
        #expect(qr.reference == "INV-2041")
        #expect(qr.merchantName == "TAN AH SENG")
    }

    @Test func readsTheUENSampleWithAnEditableAmount() throws {
        let qr = try SGQR.parse(SGQRSample.uen.raw)
        #expect(qr.proxyType == .uen)
        #expect(qr.proxyValue == "201912345K")
        #expect(qr.amountEditable)
        #expect(qr.amount == nil)
    }

    @Test func readsTheRejectAndSlowSamples() throws {
        #expect(try SGQR.parse(SGQRSample.rejected.raw).proxyValue == "90000002")
        #expect(try SGQR.parse(SGQRSample.slow.raw).amount == "3.20")
    }

    @Test func rejectsANETSOnlySGQRAsNotPayNow() {
        #expect(throws: SGQRError.notPayNow) { try SGQR.parse(SGQRSample.nets.raw) }
        #expect(SGQRError.notPayNow.localizedDescription == "This QR isn't a PayNow code")
    }

    @Test(arguments: ["hello", "https://example.com", ""])
    func rejectsPlainTextAndURLs(_ text: String) {
        #expect(throws: SGQRError.notPayNow) { try SGQR.parse(text) }
    }

    @Test func failsTheCRCWhenAByteChanges() {
        let raw = SGQRSample.mobile.raw.replacingOccurrences(of: "12.50", with: "92.50")
        #expect(throws: SGQRError.checksumMismatch) { try SGQR.parse(raw) }
        #expect(SGQRError.checksumMismatch.localizedDescription == "This QR code couldn't be read. Try again.")
    }

    @Test func acceptsALowercaseCRC() throws {
        let raw = SGQRSample.uen.raw
        #expect(try SGQR.parse(String(raw.dropLast(4)) + raw.suffix(4).lowercased()).proxyValue == "201912345K")
    }

    @Test func findsPayNowInAnyMerchantTemplateFrom26To51() throws {
        let raw = SGQR.encode(.init(proxyType: .mobile, proxyValue: "98765432"))
            .replacingOccurrences(of: "2638", with: "5138")
        let body = String(raw.dropLast(4))
        #expect(try SGQR.parse(body + SGQR.crc16(body)).proxyValue == "98765432")
    }

    @Test func skipsOtherTemplatesBeforePayNow() throws {
        let other = field("00", "COM.EXAMPLE") + field("01", "X")
        let paynow = field("00", "SG.PAYNOW") + field("01", "0") + field("02", "+65 9876-5432") + field("03", "1")
        let body = field("00", "01") + field("01", "11") + field("26", other) + field("27", paynow) + "6304"
        #expect(try SGQR.parse(body + SGQR.crc16(body)).proxyValue == "98765432")
    }

    @Test func rejectsAnUnsupportedProxyType() {
        var s = field("00", "01") + field("26", field("00", "SG.PAYNOW") + field("01", "3") + field("02", "S1234567A")) + "6304"
        s += SGQR.crc16(s)
        #expect(throws: SGQRError.notPayNow) { try SGQR.parse(s) }
    }

    @Test func treatsAMissingAmountAsEditable() throws {
        let raw = SGQR.encode(.init(proxyType: .mobile, proxyValue: "91234567", amountEditable: false))
        #expect(try SGQR.parse(raw).amountEditable)
    }

    @Test func encodeRoundTripsAndMatchesTheTSBuilder() throws {
        let raw = SGQR.encode(.init(proxyType: .uen, proxyValue: "201912345K", amountEditable: true,
                                    merchantName: "KOPI CORNER PTE LTD"))
        #expect(raw == SGQRSample.uen.raw)
    }

    @Test func validatesProxies() {
        #expect(SGQR.isValidProxy(.mobile, "91234567"))
        #expect(SGQR.isValidProxy(.mobile, "81234567"))
        #expect(!SGQR.isValidProxy(.mobile, "61234567"))
        #expect(!SGQR.isValidProxy(.mobile, "9123456"))
        #expect(SGQR.isValidProxy(.uen, "201912345K"))
        #expect(SGQR.isValidProxy(.uen, "53312345D"))
        #expect(!SGQR.isValidProxy(.uen, "12345678"))
        #expect(!SGQR.isValidProxy(.uen, "12345678901"))
        #expect(SGQR.normalizeMobile("+65 9123 4567") == "91234567")
    }
}
