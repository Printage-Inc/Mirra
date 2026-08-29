import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreMedia
import CoreMediaIO
import Foundation
import OSLog
import ServiceManagement

final class MirrorController: ObservableObject {
    private static let logger = Logger(subsystem: "app.mirra.mac", category: "AutomaticLaunch")

    struct DeviceOption: Identifiable, Hashable {
        let id: String
        let name: String
        let manufacturer: String
        let modelID: String
        let connectionKind: CaptureConnectionKind

        var detail: String {
            [connectionKind.localizedLabel, manufacturer, modelID]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
    }

    enum State: Equatable {
        case idle
        case requestingPermission
        case permissionDenied
        case waitingForDevice
        case connecting(String)
        case streaming(String)
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                return "準備中"
            case .requestingPermission:
                return "等待相機權限"
            case .permissionDenied:
                return "需要相機權限"
            case .waitingForDevice:
                return "搜尋 iPhone／iPad（USB）"
            case .connecting(let name):
                return "正在連接 \(name)"
            case .streaming(let name):
                return "正在顯示 \(name)"
            case .failed(let message):
                return message
            }
        }
    }

    enum AutoLaunchState: Equatable {
        case checking
        case enabled
        case requiresApproval
        case needsInstallation
        case unavailable
        case failed(String)

        var diagnosticValue: String {
            switch self {
            case .checking: return "checking"
            case .enabled: return "enabled"
            case .requiresApproval: return "requiresApproval"
            case .needsInstallation: return "needsInstallation"
            case .unavailable: return "unavailable"
            case .failed(let message): return "failed: \(message)"
            }
        }
    }

    @Published private(set) var devices: [DeviceOption] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var autoLaunchState: AutoLaunchState = .checking
    @Published private(set) var videoAspectRatio: CGFloat?
    @Published var selectedDeviceID: String?
    @Published var presentationMode = true

    let captureSession: AVCaptureSession

    private let coreMediaIOPreparation: CoreMediaIOPreparation
    private let sessionQueue = DispatchQueue(label: "app.mirra.capture-session")
    private var discoverySession: AVCaptureDevice.DiscoverySession?
    private var activeInput: AVCaptureDeviceInput?
    private var notificationTokens: [NSObjectProtocol] = []
    private var devicePollTimer: Timer?
    private var hasStarted = false
    private var autoLaunchServiceStatus = "unknown"

    init() {
        // CoreMediaIO must expose iOS screen devices before the first
        // AVFoundation object initializes the capture-device subsystem.
        coreMediaIOPreparation = Self.prepareScreenCaptureDevices()
        captureSession = AVCaptureSession()
        installDeviceObservers()
    }

    deinit {
        devicePollTimer?.invalidate()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        captureSession.stopRunning()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        configureAutomaticLaunch()

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startDevicePolling()
            refreshDevices()
        case .notDetermined:
            state = .requestingPermission
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.startDevicePolling()
                        self.refreshDevices()
                    } else {
                        self.state = .permissionDenied
                    }
                }
            }
        case .denied, .restricted:
            state = .permissionDenied
        @unknown default:
            state = .failed("無法判斷相機權限")
        }
    }

    func refreshDevices() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            state = .permissionDenied
            return
        }

        let discovery = makeDiscoverySession()
        discoverySession = discovery

        let availableDevices = discovery.devices.filter { device in
            ScreenCaptureSourceFilter.accepts(
                name: device.localizedName,
                manufacturer: device.manufacturer,
                modelID: device.modelID,
                isContinuityCamera: device.isContinuityCamera,
                transportType: device.transportType
            )
        }

        let previouslyHadMobileDevice = !devices.isEmpty
        devices = availableDevices
            .map {
                DeviceOption(
                    id: $0.uniqueID,
                    name: $0.localizedName,
                    manufacturer: $0.manufacturer,
                    modelID: $0.modelID,
                    connectionKind: ScreenCaptureSourceFilter.connectionKind(
                        transportType: $0.transportType
                    )
                )
            }
            .sorted { lhs, rhs in
                if lhs.connectionKind.priority != rhs.connectionKind.priority {
                    return lhs.connectionKind.priority < rhs.connectionKind.priority
                }
                let lhsPriority = Self.mobileDevicePriority(lhs)
                let rhsPriority = Self.mobileDevicePriority(rhs)
                return lhsPriority == rhsPriority
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : lhsPriority < rhsPriority
            }

        if !previouslyHadMobileDevice, !devices.isEmpty {
            activateApplicationWindow()
        }

        guard !devices.isEmpty else {
            selectedDeviceID = nil
            if captureSession.isRunning || activeInput != nil {
                stopCapture()
            }
            videoAspectRatio = nil
            state = .waitingForDevice
            return
        }

        let selectedStillExists = devices.contains { $0.id == selectedDeviceID }
        if !selectedStillExists {
            selectedDeviceID = devices[0].id
        }

        let alreadyStreamingSelectedDevice = captureSession.isRunning
            && activeInput?.device.uniqueID == selectedDeviceID
        if let selectedDeviceID, !alreadyStreamingSelectedDevice {
            connect(to: selectedDeviceID)
        }
    }

    func selectDevice(_ id: String) {
        guard id != selectedDeviceID || !captureSession.isRunning else { return }
        selectedDeviceID = id
        connect(to: id)
    }

    func copyDiagnostics() {
        let authorization: String
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorization = "authorized"
        case .denied: authorization = "denied"
        case .restricted: authorization = "restricted"
        case .notDetermined: authorization = "notDetermined"
        @unknown default: authorization = "unknown"
        }

        let captureDevices = discoverySession?.devices ?? []
        let deviceReports: [[String: Any]] = captureDevices.map { device in
            let formats: [[String: Any]] = device.formats.map { format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let frameRates = format.videoSupportedFrameRateRanges.map {
                    [
                        "minimum": $0.minFrameRate,
                        "maximum": $0.maxFrameRate
                    ]
                }

                return [
                    "width": Int(dimensions.width),
                    "height": Int(dimensions.height),
                    "frameRates": frameRates
                ]
            }

            return [
                "name": device.localizedName,
                "manufacturer": device.manufacturer,
                "modelID": device.modelID,
                "deviceType": device.deviceType.rawValue,
                "connectionKind": ScreenCaptureSourceFilter.connectionKind(
                    transportType: device.transportType
                ).rawValue,
                "transportType": device.transportType,
                "transportFourCC": ScreenCaptureSourceFilter.fourCharacterCode(device.transportType),
                "isContinuityCamera": device.isContinuityCamera,
                "mediaTypes": [
                    "video": device.hasMediaType(.video),
                    "audio": device.hasMediaType(.audio),
                    "muxed": device.hasMediaType(.muxed)
                ],
                "formats": formats
            ]
        }

        let report: [String: Any] = [
            "app": "Mirra",
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            "appBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
            "bundlePath": Bundle.main.bundleURL.path,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "architecture": Self.architectureName,
            "mode": "wiredOnly",
            "cameraAuthorization": authorization,
            "captureState": state.label,
            "automaticLaunch": [
                "state": autoLaunchState.diagnosticValue,
                "serviceStatus": autoLaunchServiceStatus
            ],
            "coreMediaIO": coreMediaIOPreparation.diagnostics,
            "devices": deviceReports
        ]

        guard JSONSerialization.isValidJSONObject(report),
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func updateVideoAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio.isFinite, aspectRatio > 0.1, aspectRatio < 10 else { return }
        if let current = videoAspectRatio, abs(current - aspectRatio) < 0.002 {
            return
        }
        videoAspectRatio = aspectRatio
    }

    func openLoginItemsSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func connect(to id: String) {
        guard let device = discoverySession?.devices.first(where: { $0.uniqueID == id }) else {
            state = .failed("找不到選取的裝置")
            return
        }

        let displayName = "\(device.localizedName) · USB"
        state = .connecting(displayName)

        sessionQueue.async { [weak self] in
            guard let self else { return }

            do {
                let input = try AVCaptureDeviceInput(device: device)

                self.captureSession.beginConfiguration()

                if let activeInput = self.activeInput {
                    self.captureSession.removeInput(activeInput)
                    self.activeInput = nil
                }

                if self.captureSession.canSetSessionPreset(.high) {
                    self.captureSession.sessionPreset = .high
                }

                guard self.captureSession.canAddInput(input) else {
                    self.captureSession.commitConfiguration()
                    throw CaptureError.cannotAddInput
                }

                self.captureSession.addInput(input)
                self.activeInput = input
                self.captureSession.commitConfiguration()

                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }

                let dimensions = CMVideoFormatDescriptionGetPresentationDimensions(
                    device.activeFormat.formatDescription,
                    usePixelAspectRatio: true,
                    useCleanAperture: true
                )

                DispatchQueue.main.async {
                    if dimensions.width > 0, dimensions.height > 0 {
                        self.updateVideoAspectRatio(dimensions.width / dimensions.height)
                    }
                    self.state = .streaming(displayName)
                }
            } catch {
                DispatchQueue.main.async {
                    self.state = .failed("連接失敗：\(error.localizedDescription)")
                }
            }
        }
    }

    private func stopCapture() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            self.captureSession.beginConfiguration()
            if let activeInput = self.activeInput {
                self.captureSession.removeInput(activeInput)
                self.activeInput = nil
            }
            self.captureSession.commitConfiguration()
        }
    }

    private func makeDiscoverySession() -> AVCaptureDevice.DiscoverySession {
        if #available(macOS 14.0, *) {
            return AVCaptureDevice.DiscoverySession(
                // The wired iOS display is still published by Apple's legacy
                // iOSScreenCapture DAL plug-in as ExternalUnknown on current
                // macOS releases. Query both values: External covers modern
                // CMIO extensions, while ExternalUnknown covers the QuickTime
                // compatible wired-screen source.
                deviceTypes: [.external, .externalUnknown],
                // QuickTime's wired iOS screen source can be published as a
                // muxed (screen video + device audio) DAL device. Passing nil
                // includes both muxed and video-only devices; the source
                // filter below still excludes webcams and virtual cameras.
                mediaType: nil,
                position: .unspecified
            )
        }

        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.externalUnknown],
            mediaType: nil,
            position: .unspecified
        )
    }

    private func installDeviceObservers() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .AVCaptureDeviceWasConnected,
            .AVCaptureDeviceWasDisconnected
        ]

        notificationTokens = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshDevices()
            }
        }
    }

    private func startDevicePolling() {
        guard devicePollTimer == nil else { return }
        devicePollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            guard let self, !self.captureSession.isRunning else { return }
            self.refreshDevices()
        }
    }

    private func configureAutomaticLaunch() {
        guard #available(macOS 13.0, *) else {
            autoLaunchState = .unavailable
            return
        }

        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let agentPlistURL = bundleURL
            .appendingPathComponent("Contents/Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(Self.deviceWatcherPlistName)

        guard bundleURL.pathExtension == "app",
              !bundleURL.path.hasPrefix("/Volumes/"),
              FileManager.default.fileExists(atPath: agentPlistURL.path) else {
            autoLaunchServiceStatus = "bundleNotInstalled"
            autoLaunchState = .needsInstallation
            return
        }

        let service = SMAppService.agent(plistName: Self.deviceWatcherPlistName)
        do {
            let initialStatus = service.status
            autoLaunchServiceStatus = Self.serviceStatusName(initialStatus)
            Self.logger.info("USB watcher initial status: \(self.autoLaunchServiceStatus, privacy: .public)")

            // Apple's reference implementation registers the service directly.
            // Some macOS releases report .notFound for an embedded agent that
            // has never been registered. Treat it as an initial state and let
            // register() return the authoritative result.
            if initialStatus == .notRegistered || initialStatus == .notFound {
                try service.register()
            }

            let finalStatus = service.status
            autoLaunchServiceStatus = Self.serviceStatusName(finalStatus)
            autoLaunchState = Self.autoLaunchState(for: finalStatus)
            Self.logger.info("USB watcher final status: \(self.autoLaunchServiceStatus, privacy: .public)")
        } catch {
            autoLaunchServiceStatus = "registrationError: \(error.localizedDescription)"
            autoLaunchState = .failed(error.localizedDescription)
            Self.logger.error("USB watcher registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @available(macOS 13.0, *)
    private static func autoLaunchState(for status: SMAppService.Status) -> AutoLaunchState {
        switch status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .failed("not registered")
        case .notFound: return .failed("找不到內建的接線啟動服務；請重新安裝正式簽署版")
        @unknown default: return .failed("unknown ServiceManagement status")
        }
    }

    @available(macOS 13.0, *)
    private static func serviceStatusName(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requiresApproval"
        case .notRegistered: return "notRegistered"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }

    private func activateApplicationWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.bringMainWindowForward()
        }
    }

    private func bringMainWindowForward() {
        // Bring the existing Mirra window forward when a new USB device is
        // detected. Never resize the window or foreground permission panels.
        let mirraWindow = NSApp.windows
            .filter { window in
                window.canBecomeKey
                    && !window.isSheet
                    && !(window is NSPanel)
                    && window.styleMask.contains(.titled)
            }
            .max { lhs, rhs in
                lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
            }

        guard let mirraWindow else { return }
        mirraWindow.collectionBehavior = [.managed, .fullScreenNone]
        if mirraWindow.isMiniaturized {
            mirraWindow.deminiaturize(nil)
        }
        mirraWindow.orderFrontRegardless()
        mirraWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func prepareScreenCaptureDevices() -> CoreMediaIOPreparation {
        let systemObject = CMIOObjectID(kCMIOObjectSystemObject)
        let uint32Size = UInt32(MemoryLayout<UInt32>.size)

        var screenCaptureAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var enabled: UInt32 = 1
        let screenCaptureSetStatus = CMIOObjectSetPropertyData(
            systemObject,
            &screenCaptureAddress,
            0,
            nil,
            uint32Size,
            &enabled
        )

        var screenCaptureReadValue: UInt32 = 0
        var screenCaptureReadSize = uint32Size
        let screenCaptureReadStatus = CMIOObjectGetPropertyData(
            systemObject,
            &screenCaptureAddress,
            0,
            nil,
            screenCaptureReadSize,
            &screenCaptureReadSize,
            &screenCaptureReadValue
        )

        // Merely opting into screen-capture devices does not force macOS 26
        // to instantiate the legacy DAL plug-in used by QuickTime Player for
        // wired iPhone/iPad display capture. Querying the public plug-in
        // property asks CoreMediaIO to load it before AVFoundation discovers
        // devices.
        var plugInAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyPlugInForBundleID),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var plugInBundleID: CFString = "com.apple.cmio.DAL.iOSScreenCapture" as CFString
        var plugInObjectID = CMIOObjectID(kCMIOObjectUnknown)
        let plugInLoadStatus: OSStatus = withUnsafeMutablePointer(to: &plugInBundleID) { bundleIDPointer in
            withUnsafeMutablePointer(to: &plugInObjectID) { objectIDPointer in
                var translation = AudioValueTranslation(
                    mInputData: UnsafeMutableRawPointer(bundleIDPointer),
                    mInputDataSize: UInt32(MemoryLayout<CFString>.size),
                    mOutputData: UnsafeMutableRawPointer(objectIDPointer),
                    mOutputDataSize: UInt32(MemoryLayout<CMIOObjectID>.size)
                )
                var translationSize = UInt32(MemoryLayout<AudioValueTranslation>.size)
                return CMIOObjectGetPropertyData(
                    systemObject,
                    &plugInAddress,
                    0,
                    nil,
                    translationSize,
                    &translationSize,
                    &translation
                )
            }
        }

        return CoreMediaIOPreparation(
            screenCaptureSetStatus: screenCaptureSetStatus,
            screenCaptureReadStatus: screenCaptureReadStatus,
            screenCaptureReadValue: screenCaptureReadValue,
            plugInLoadStatus: plugInLoadStatus,
            plugInObjectID: plugInObjectID
        )
    }

    private static func mobileDevicePriority(_ device: DeviceOption) -> Int {
        let text = "\(device.name) \(device.modelID)".lowercased()
        let mobileMarkers = ["iphone", "ipad", "ipod", "apple tv", "vision"]
        if mobileMarkers.contains(where: text.contains) {
            return 0
        }
        if device.manufacturer == "Apple Inc." {
            return 1
        }
        return 2
    }

    private static var architectureName: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static let deviceWatcherPlistName = "app.mirra.device-watcher.plist"

    private struct CoreMediaIOPreparation {
        let screenCaptureSetStatus: OSStatus
        let screenCaptureReadStatus: OSStatus
        let screenCaptureReadValue: UInt32
        let plugInLoadStatus: OSStatus
        let plugInObjectID: CMIOObjectID

        var diagnostics: [String: Any] {
            [
                "screenCaptureDeviceOptIn": [
                    "setStatus": screenCaptureSetStatus,
                    "readStatus": screenCaptureReadStatus,
                    "value": screenCaptureReadValue
                ],
                "iOSScreenCapturePlugin": [
                    "bundleID": "com.apple.cmio.DAL.iOSScreenCapture",
                    "loadStatus": plugInLoadStatus,
                    "objectID": plugInObjectID
                ]
            ]
        }
    }

    private enum CaptureError: LocalizedError {
        case cannotAddInput

        var errorDescription: String? {
            "macOS 無法把這個裝置加入擷取工作階段"
        }
    }
}
