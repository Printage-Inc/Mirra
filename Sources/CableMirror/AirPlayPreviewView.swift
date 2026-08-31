import AVFoundation
import CoreMedia
import CoreVideo
import SwiftUI

/// Bridges decoded AirPlay pixel buffers to an AVSampleBufferDisplayLayer.
/// Frames stay on a serial media queue so SwiftUI does not receive a state
/// update for every video frame.
final class AirPlayFrameRenderer {
    private let renderQueue = DispatchQueue(
        label: "app.mirra.airplay-renderer",
        qos: .userInteractive
    )
    private let layerLock = NSLock()
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private var formatDescription: CMVideoFormatDescription?
    private var formatSignature: FormatSignature?

    var onAspectRatioChange: ((CGFloat) -> Void)?

    func attach(_ layer: AVSampleBufferDisplayLayer) {
        layerLock.lock()
        displayLayer = layer
        layerLock.unlock()
    }

    func detach(_ layer: AVSampleBufferDisplayLayer) {
        layerLock.lock()
        if displayLayer === layer {
            displayLayer = nil
        }
        layerLock.unlock()
    }

    func enqueue(_ pixelBuffer: CVPixelBuffer, presentationTimeNanoseconds: UInt64) {
        renderQueue.async { [weak self, pixelBuffer] in
            self?.render(pixelBuffer, presentationTimeNanoseconds: presentationTimeNanoseconds)
        }
    }

    func clear() {
        renderQueue.async { [weak self] in
            guard let layer = self?.currentLayer() else { return }
            layer.flushAndRemoveImage()
        }
    }

    private func render(_ pixelBuffer: CVPixelBuffer, presentationTimeNanoseconds: UInt64) {
        guard let layer = currentLayer() else { return }

        let signature = FormatSignature(pixelBuffer: pixelBuffer)
        if signature != formatSignature {
            var newDescription: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer,
                formatDescriptionOut: &newDescription
            )
            guard status == noErr, let newDescription else { return }
            formatDescription = newDescription
            formatSignature = signature

            let aspectRatio = CGFloat(signature.width) / CGFloat(signature.height)
            DispatchQueue.main.async { [weak self] in
                self?.onAspectRatioChange?(aspectRatio)
            }
        }

        guard let formatDescription else { return }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(
                value: Int64(clamping: presentationTimeNanoseconds),
                timescale: 1_000_000_000
            ),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else { return }

        CMSetAttachment(
            sampleBuffer,
            key: kCMSampleAttachmentKey_DisplayImmediately,
            value: kCFBooleanTrue,
            attachmentMode: kCMAttachmentMode_ShouldPropagate
        )
        if layer.status == .failed {
            layer.flush()
        }
        layer.enqueue(sampleBuffer)
    }

    private func currentLayer() -> AVSampleBufferDisplayLayer? {
        layerLock.lock()
        defer { layerLock.unlock() }
        return displayLayer
    }

    private struct FormatSignature: Equatable {
        let width: Int
        let height: Int
        let pixelFormat: OSType

        init(pixelBuffer: CVPixelBuffer) {
            width = CVPixelBufferGetWidth(pixelBuffer)
            height = CVPixelBufferGetHeight(pixelBuffer)
            pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        }
    }
}

struct AirPlayPreviewView: NSViewRepresentable {
    let renderer: AirPlayFrameRenderer

    func makeNSView(context: Context) -> AirPlayPreviewNSView {
        let view = AirPlayPreviewNSView()
        renderer.attach(view.displayLayer)
        return view
    }

    func updateNSView(_ nsView: AirPlayPreviewNSView, context: Context) {
        renderer.attach(nsView.displayLayer)
    }

    static func dismantleNSView(_ nsView: AirPlayPreviewNSView, coordinator: ()) {
        nsView.displayLayer.flushAndRemoveImage()
    }
}

final class AirPlayPreviewNSView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        layer?.addSublayer(displayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}
