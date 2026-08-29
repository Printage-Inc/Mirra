import AVFoundation
import CoreAudio
import CoreMediaIO
import Foundation

var screenAddress = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
)
var screenEnabled: UInt32 = 1
let screenSetStatus = CMIOObjectSetPropertyData(
    CMIOObjectID(kCMIOObjectSystemObject),
    &screenAddress,
    0,
    nil,
    UInt32(MemoryLayout<UInt32>.size),
    &screenEnabled
)
var screenReadBack: UInt32 = 0
var screenReadSize = UInt32(MemoryLayout<UInt32>.size)
let screenGetStatus = CMIOObjectGetPropertyData(
    CMIOObjectID(kCMIOObjectSystemObject),
    &screenAddress,
    0,
    nil,
    screenReadSize,
    &screenReadSize,
    &screenReadBack
)
var screenIsSettable = DarwinBoolean(false)
let screenSettableStatus = CMIOObjectIsPropertySettable(
    CMIOObjectID(kCMIOObjectSystemObject),
    &screenAddress,
    &screenIsSettable
)
print("screen property setStatus=\(screenSetStatus), getStatus=\(screenGetStatus), value=\(screenReadBack), settableStatus=\(screenSettableStatus), settable=\(screenIsSettable.boolValue)")

var plugInAddress = CMIOObjectPropertyAddress(
    mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyPlugInForBundleID),
    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
)
func loadPlugIn(bundleID: String) -> (OSStatus, CMIOObjectID) {
    var plugInBundleID: CFString = bundleID as CFString
    var plugInObjectID = CMIOObjectID(kCMIOObjectUnknown)
    let status: OSStatus = withUnsafeMutablePointer(to: &plugInBundleID) { bundleIDPointer in
        withUnsafeMutablePointer(to: &plugInObjectID) { objectIDPointer in
        var translation = AudioValueTranslation(
            mInputData: UnsafeMutableRawPointer(bundleIDPointer),
            mInputDataSize: UInt32(MemoryLayout<CFString>.size),
            mOutputData: UnsafeMutableRawPointer(objectIDPointer),
            mOutputDataSize: UInt32(MemoryLayout<CMIOObjectID>.size)
        )
        var translationSize = UInt32(MemoryLayout<AudioValueTranslation>.size)
            return CMIOObjectGetPropertyData(
                CMIOObjectID(kCMIOObjectSystemObject),
                &plugInAddress,
                0,
                nil,
                translationSize,
                &translationSize,
                &translation
            )
        }
    }
    return (status, plugInObjectID)
}

for bundleID in [
    "com.apple.cmio.DAL.ACD",
    "com.apple.cmio.DAL.iOSScreenCapture",
    "com.apple.cmio.DAL.VDC-4"
] {
    let result = loadPlugIn(bundleID: bundleID)
    print("plug-in \(bundleID) status=\(result.0), objectID=\(result.1)")
}

Thread.sleep(forTimeInterval: 5)

let discovery: AVCaptureDevice.DiscoverySession
if #available(macOS 14.0, *) {
    discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.external, .externalUnknown],
        mediaType: nil,
        position: .unspecified
    )
} else {
    discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.externalUnknown],
        mediaType: nil,
        position: .unspecified
    )
}

for device in discovery.devices {
    let dimensions = device.formats.map {
        let size = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
        return "\(size.width)x\(size.height)"
    }
    print("name=\(device.localizedName)")
    print("manufacturer=\(device.manufacturer)")
    print("modelID=\(device.modelID)")
    print("deviceType=\(device.deviceType.rawValue)")
    print("transportType=\(device.transportType)")
    print("continuityCamera=\(device.isContinuityCamera)")
    print("mediaTypes=video:\(device.hasMediaType(.video)),audio:\(device.hasMediaType(.audio)),muxed:\(device.hasMediaType(.muxed))")
    print("formats=\(dimensions.joined(separator: ","))")
    print("---")
}
