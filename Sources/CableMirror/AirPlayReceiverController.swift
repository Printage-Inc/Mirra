import AirPlayMacBridge
import Combine
import CoreVideo
import Foundation
import OSLog

final class AirPlayReceiverController: ObservableObject {
    private static let logger = Logger(
        subsystem: "app.mirra.mac",
        category: "AirPlayReceiver"
    )

    enum State: Equatable {
        case stopped
        case starting
        case advertising
        case streaming
        case failed(String)

        var diagnosticValue: String {
            switch self {
            case .stopped: return "stopped"
            case .starting: return "starting"
            case .advertising: return "advertising"
            case .streaming: return "streaming"
            case .failed(let message): return "failed: \(message)"
            }
        }
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var hasReceivedFrame = false
    @Published private(set) var verificationCode: String?

    let renderer = AirPlayFrameRenderer()
    let receiverName: String

    var onFirstFrame: (() -> Void)?
    var onConnectionLost: (() -> Void)?
    var onVerificationCode: ((String) -> Void)?

    private let engine: AirPlayEngine
    private var started = false
    private var verificationGeneration = 0

    init() {
        let macName = Host.current().localizedName?
            .replacingOccurrences(of: ".local", with: "") ?? "Mac"
        receiverName = "Mirra: \(macName)"
        engine = AirPlayEngine(name: receiverName)

        engine.onVideoFrame = { [weak self] pixelBuffer, timestamp in
            guard let self else { return }
            self.renderer.enqueue(
                pixelBuffer,
                presentationTimeNanoseconds: timestamp
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.hasReceivedFrame else { return }
                self.hasReceivedFrame = true
                self.verificationGeneration += 1
                self.verificationCode = nil
                self.state = .streaming
                self.onFirstFrame?()
            }
        }

        engine.onConnectionLost = { [weak self] in
            self?.renderer.clear()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let wasStreaming = self.hasReceivedFrame
                self.hasReceivedFrame = false
                self.state = .advertising

                // PAIR-PIN-START is a short preliminary connection. iOS closes
                // it immediately after asking the receiver to display a code,
                // then waits for the user before opening the authenticated
                // connection. Keep that code visible; this close is not a
                // mirroring-session loss.
                if self.verificationCode != nil, !wasStreaming {
                    Self.logger.debug("Keeping AirPlay verification code after pairing preflight closed")
                    return
                }

                self.verificationGeneration += 1
                self.verificationCode = nil
                if wasStreaming {
                    self.onConnectionLost?()
                }
            }
        }

        engine.onVerificationCode = { [weak self] code in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                Self.logger.notice("AirPlay verification code received from receiver core")
                self.verificationGeneration += 1
                let generation = self.verificationGeneration
                self.verificationCode = code
                self.onVerificationCode?(code)

                // If the sender cancels the password sheet, UxPlay has no
                // separate callback that distinguishes cancellation from the
                // expected pairing preflight close. Expire the stale display
                // without ever logging or persisting the secret.
                DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
                    guard let self,
                          self.verificationGeneration == generation,
                          !self.hasReceivedFrame else { return }
                    self.verificationGeneration += 1
                    self.verificationCode = nil
                }
            }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        state = .starting

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.engine.start()
            let port = self.engine.serverPort()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.state = port == 0
                    ? .failed("AirPlay 接收器無法啟動")
                    : .advertising
            }
        }
    }

    func stop() {
        guard started else { return }
        started = false
        renderer.clear()
        state = .stopped
        hasReceivedFrame = false
        verificationGeneration += 1
        verificationCode = nil
        DispatchQueue.global(qos: .userInitiated).async { [engine] in
            engine.stop()
        }
    }

    deinit {
        engine.stop()
    }
}
