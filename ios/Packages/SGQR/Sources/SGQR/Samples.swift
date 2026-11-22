/// The shared sample codes from `web/app/packages/sgqr/samples/index.json`.
public enum SGQRSample: String, CaseIterable, Sendable {
    case mobile = "mobile-91234567-12.50"
    case uen = "uen-201912345K-editable"
    case nets = "not-paynow-nets"
    case rejected = "mobile-90000002-rejected"
    case slow = "mobile-90000001-slow"

    public var raw: String {
        switch self {
        case .mobile:
            "00020101021226500009SG.PAYNOW010100211+659123456703010040820301231520400005303702540512.505802SG5911TAN AH SENG6009Singapore62120108INV-204163046261"
        case .uen:
            "00020101021126370009SG.PAYNOW010120210201912345K030115204000053037025802SG5919KOPI CORNER PTE LTD6009Singapore6304839B"
        case .nets:
            "00020101021133290011SG.COM.NETS011012345678905204581253037025802SG5912HAWKER STALL6009Singapore63040253"
        case .rejected:
            "00020101021226380009SG.PAYNOW010100211+65900000020301052040000530370254045.005802SG5913REJECTED DEMO6009Singapore6304F141"
        case .slow:
            "00020101021226380009SG.PAYNOW010100211+65900000010301152040000530370254043.205802SG5909SLOW DEMO6009Singapore6304CF87"
        }
    }
}
