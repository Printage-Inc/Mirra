import Foundation

enum CaptureConnectionKind: String, Hashable {
    case wired
    case wireless
    case unknown

    var localizedLabel: String {
        switch self {
        case .wired: return "USB"
        case .wireless: return "不支援的無線來源"
        case .unknown: return "USB"
        }
    }

    var priority: Int {
        switch self {
        case .wired: return 0
        case .unknown: return 1
        case .wireless: return 2
        }
    }
}

enum ScreenCaptureSourceFilter {
    static func accepts(
        name: String,
        manufacturer: String,
        modelID: String,
        isContinuityCamera: Bool,
        transportType: Int32
    ) -> Bool {
        guard !isContinuityCamera,
              connectionKind(transportType: transportType) != .wireless else {
            return false
        }

        let normalizedModelID = modelID.lowercased()
        let mobileModelPrefixes = ["iphone", "ipad", "ipod"]
        if mobileModelPrefixes.contains(where: normalizedModelID.hasPrefix) {
            return true
        }

        let normalizedManufacturer = manufacturer
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedManufacturer == "apple inc." || normalizedManufacturer == "apple" else {
            return false
        }

        let description = "\(name) \(modelID)".lowercased()
        let cameraOnlyMarkers = [
            "facetime",
            "studio display",
            "desk view"
        ]

        return !cameraOnlyMarkers.contains(where: description.contains)
    }

    static func connectionKind(transportType: Int32) -> CaptureConnectionKind {
        switch fourCharacterCode(transportType) {
        case "usb ":
            return .wired
        case "wrls", "ntwk", "blue":
            return .wireless
        default:
            return .unknown
        }
    }

    static func fourCharacterCode(_ value: Int32) -> String {
        let code = UInt32(bitPattern: value)
        let bytes = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        guard bytes.allSatisfy({ 32...126 ~= $0 }) else {
            return String(format: "0x%08X", code)
        }
        return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", code)
    }
}
