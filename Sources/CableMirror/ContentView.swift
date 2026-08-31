import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var mirror: MirrorController
    @State private var alwaysOnTop = false
    @State private var diagnosticsCopied = false
    @State private var presentationControlsVisible = false

    var body: some View {
        VStack(spacing: 0) {
            if !mirror.presentationMode {
                toolbar
            }

            ZStack {
                Color.black
                VideoPreviewView(
                    session: mirror.captureSession,
                    onVideoAspectRatioChange: mirror.updateVideoAspectRatio
                )
                .opacity(mirror.isShowingUSBPreview ? 1 : 0)

                AirPlayPreviewView(renderer: mirror.airPlayReceiver.renderer)
                    .opacity(mirror.isShowingAirPlayPreview ? 1 : 0)

                if !isShowingPreview {
                    emptyState
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: mirror.presentationMode ? 0 : 22, style: .continuous))
            .onHover { isHovering in
                presentationControlsVisible = isHovering
            }
            .overlay(alignment: .topTrailing) {
                if mirror.presentationMode && presentationControlsVisible {
                    Button {
                        mirror.presentationMode = false
                    } label: {
                        Label("離開簡報模式", systemImage: "rectangle.compress.vertical")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(12)
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
            }
            .padding(.horizontal, mirror.presentationMode ? 0 : 18)
            .padding(.bottom, mirror.presentationMode ? 0 : 14)

            if !mirror.presentationMode {
                footer
            }
        }
        .frame(
            minWidth: mirror.presentationMode ? 260 : 390,
            minHeight: mirror.presentationMode ? 420 : 560
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            WindowConfiguration(alwaysOnTop: alwaysOnTop)
        )
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Mirra")
                    .font(.headline)
                Label(mirror.state.label, systemImage: stateSymbol)
                    .font(.caption)
                    .foregroundStyle(stateColor)
            }

            Spacer()

            Picker("連線", selection: $mirror.connectionPreference) {
                ForEach(MirrorController.ConnectionPreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 155)

            if !mirror.devices.isEmpty {
                Picker("裝置", selection: deviceSelection) {
                    ForEach(mirror.devices) { device in
                        VStack(alignment: .leading) {
                            Text(device.name)
                            if !device.detail.isEmpty {
                                Text(device.detail)
                            }
                        }
                        .tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 210)
            }

            Button {
                mirror.refreshDevices()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("重新掃描裝置")

            Button {
                mirror.presentationMode = true
            } label: {
                Image(systemName: "rectangle.expand.vertical")
            }
            .buttonStyle(.borderless)
            .help("進入簡報模式（⇧⌘P）")
        }
        .padding(18)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: emptyStateSymbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(emptyStateSecondaryColor)

            Text(emptyStateTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(mirror.presentationMode ? Color.white : Color.primary)

            Text(emptyStateMessage)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(emptyStateSecondaryColor)
                .frame(maxWidth: 330)

            if let code = mirror.airPlayVerificationCode {
                VStack(spacing: 6) {
                    Text("AirPlay 驗證碼")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(emptyStateSecondaryColor)
                    Text(code)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .tracking(8)
                        .foregroundStyle(mirror.presentationMode ? Color.white : Color.primary)
                        .accessibilityLabel("AirPlay 驗證碼 \(code)")
                }
                .padding(.vertical, 8)
            }

            if mirror.airPlayVerificationCode == nil {
                automaticLaunchNotice
            }

            if mirror.state == .permissionDenied {
                Button("開啟相機權限設定") {
                    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(32)
    }

    @ViewBuilder
    private var automaticLaunchNotice: some View {
        switch mirror.autoLaunchState {
        case .needsInstallation:
            Label("將 Mirra 拖到「應用程式」並重新開啟，即可啟用接線自動啟動。", systemImage: "arrow.down.app")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(emptyStateSecondaryColor)
                .frame(maxWidth: 330)
        case .requiresApproval:
            Button("允許接線時自動開啟") {
                mirror.openLoginItemsSettings()
            }
        case .failed(let message):
            Text("自動啟動尚未啟用：\(message)")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(emptyStateSecondaryColor)
                .frame(maxWidth: 330)
        default:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Toggle("浮在最上層", isOn: $alwaysOnTop)
                .toggleStyle(.switch)
                .controlSize(.small)

            Spacer()

            Text("會議中分享「Mirra」視窗；USB 與 AirPlay 都不影響手機觸控")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(diagnosticsCopied ? "已複製" : "複製診斷") {
                mirror.copyDiagnostics()
                diagnosticsCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    diagnosticsCopied = false
                }
            }
            .buttonStyle(.borderless)
            .help("複製不含裝置序號的相容性報告")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private var deviceSelection: Binding<String> {
        Binding(
            get: { mirror.selectedDeviceID ?? mirror.devices.first?.id ?? "" },
            set: { mirror.selectDevice($0) }
        )
    }

    private var isShowingPreview: Bool {
        mirror.isShowingUSBPreview || mirror.isShowingAirPlayPreview
    }

    private var stateSymbol: String {
        switch mirror.state {
        case .streaming:
            return mirror.activeSource == .airPlay
                ? "airplayvideo"
                : "cable.connector"
        case .failed, .permissionDenied:
            return "exclamationmark.triangle.fill"
        case .connecting, .requestingPermission: return "ellipsis.circle"
        default: return "iphone.gen3"
        }
    }

    private var stateColor: Color {
        switch mirror.state {
        case .streaming: return .green
        case .failed, .permissionDenied: return .orange
        default: return .secondary
        }
    }

    private var emptyStateSymbol: String {
        if mirror.airPlayVerificationCode != nil {
            return "lock.display"
        }
        switch mirror.state {
        case .permissionDenied:
            return "lock.shield"
        default:
            return "rectangle.connected.to.line.below"
        }
    }

    private var emptyStateTitle: String {
        if mirror.airPlayVerificationCode != nil {
            return "在 iPhone 輸入驗證碼"
        }
        switch mirror.state {
        case .permissionDenied:
            return "允許 Mirra 使用影像來源"
        case .failed:
            return "目前無法顯示 iPhone"
        default:
            return "連接 iPhone 或 iPad"
        }
    }

    private var emptyStateMessage: String {
        if mirror.airPlayVerificationCode != nil {
            return "驗證成功後，這台裝置 30 天內重連不需再次輸入。"
        }
        switch mirror.state {
        case .permissionDenied:
            return "macOS 把 iPhone 螢幕當成影像擷取裝置，因此 Mirra 第一次使用需要相機權限。"
        case .failed(let message):
            return "\(message)\n\n請解鎖 iPhone、點選「信任」，再重新掃描。"
        default:
            return "USB：使用資料線連接並點選「信任」。\n\n無線：確認在同一個 Wi-Fi，從控制中心 → 螢幕鏡像輸出，選擇「\(mirror.airPlayReceiver.receiverName)」。"
        }
    }

    private var emptyStateSecondaryColor: Color {
        mirror.presentationMode ? Color.white.opacity(0.72) : Color.secondary
    }
}

private struct WindowConfiguration: NSViewRepresentable {
    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = alwaysOnTop ? .floating : .normal
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.tabbingMode = .disallowed
            // Keep window geometry under the user's control. The preview is
            // independently aspect-fit, so live device rotation never crops
            // or stretches the iPhone/iPad display.
        }
    }
}
