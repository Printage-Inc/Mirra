import AVFoundation
import SwiftUI

struct VideoPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let onVideoAspectRatioChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.onVideoAspectRatioChange = onVideoAspectRatioChange
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {
        nsView.onVideoAspectRatioChange = onVideoAspectRatioChange
        if nsView.previewLayer.session !== session {
            nsView.previewLayer.session = session
        }
    }
}

final class PreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    var onVideoAspectRatioChange: ((CGFloat) -> Void)?

    private var aspectRatioTimer: Timer?
    private var lastReportedAspectRatio: CGFloat?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        aspectRatioTimer?.invalidate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        aspectRatioTimer?.invalidate()
        aspectRatioTimer = nil

        guard window != nil else { return }
        aspectRatioTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.reportVideoAspectRatioIfNeeded()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
        reportVideoAspectRatioIfNeeded()
    }

    private func reportVideoAspectRatioIfNeeded() {
        guard previewLayer.session?.isRunning == true else { return }
        let topLeft = previewLayer.layerPointConverted(
            fromCaptureDevicePoint: CGPoint(x: 0, y: 0)
        )
        let bottomRight = previewLayer.layerPointConverted(
            fromCaptureDevicePoint: CGPoint(x: 1, y: 1)
        )
        let videoSize = CGSize(
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
        guard videoSize.width > 0, videoSize.height > 0 else { return }

        let aspectRatio = videoSize.width / videoSize.height
        guard aspectRatio.isFinite, aspectRatio > 0.1, aspectRatio < 10 else { return }
        if let lastReportedAspectRatio, abs(lastReportedAspectRatio - aspectRatio) < 0.002 {
            return
        }
        lastReportedAspectRatio = aspectRatio
        onVideoAspectRatioChange?(aspectRatio)
    }
}
