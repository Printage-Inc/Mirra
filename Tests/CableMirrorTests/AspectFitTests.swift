import CoreGraphics
import XCTest
@testable import CableMirror

final class AspectFitTests: XCTestCase {
    func testRepresentativeIPhoneStreamsFitWithoutCropping() {
        let streams = [
            CGSize(width: 640, height: 1136),   // 4-inch class
            CGSize(width: 750, height: 1334),   // 4.7-inch class
            CGSize(width: 1080, height: 1920),  // common capture output
            CGSize(width: 1179, height: 2556),  // modern Dynamic Island class
            CGSize(width: 1290, height: 2796)   // modern Max class
        ]
        let containers = [
            CGSize(width: 390, height: 560),
            CGSize(width: 800, height: 600),
            CGSize(width: 1920, height: 1080)
        ]

        for stream in streams {
            for orientedStream in [stream, CGSize(width: stream.height, height: stream.width)] {
                for container in containers {
                    let fitted = AspectFit.size(content: orientedStream, inside: container)
                    XCTAssertLessThanOrEqual(fitted.width, container.width + 0.001)
                    XCTAssertLessThanOrEqual(fitted.height, container.height + 0.001)
                    XCTAssertEqual(
                        fitted.width / fitted.height,
                        orientedStream.width / orientedStream.height,
                        accuracy: 0.0001
                    )
                }
            }
        }
    }

    func testInvalidDimensionsReturnZero() {
        XCTAssertEqual(
            AspectFit.size(content: .zero, inside: CGSize(width: 100, height: 100)),
            .zero
        )
        XCTAssertEqual(
            AspectFit.size(content: CGSize(width: 100, height: 100), inside: .zero),
            .zero
        )
    }
}

final class ScreenCaptureSourceFilterTests: XCTestCase {
    func testAcceptsAppleWiredScreenSources() {
        XCTAssertTrue(
            ScreenCaptureSourceFilter.accepts(
                name: "Vivi 的 iPhone",
                manufacturer: "Apple Inc.",
                modelID: "iPhone17,1",
                isContinuityCamera: false,
                transportType: fourCC("usb ")
            )
        )
        XCTAssertTrue(
            ScreenCaptureSourceFilter.accepts(
                name: "設計測試機",
                manufacturer: "",
                modelID: "iPad16,6",
                isContinuityCamera: false,
                transportType: fourCC("othr")
            )
        )
    }

    func testRejectsVirtualAndPhysicalCameras() {
        XCTAssertFalse(
            ScreenCaptureSourceFilter.accepts(
                name: "OBS Virtual Camera",
                manufacturer: "OBS Project",
                modelID: "OBS Virtual Camera",
                isContinuityCamera: false,
                transportType: fourCC("virt")
            )
        )
        XCTAssertFalse(
            ScreenCaptureSourceFilter.accepts(
                name: "iPhone Camera",
                manufacturer: "Apple Inc.",
                modelID: "Continuity Camera",
                isContinuityCamera: true,
                transportType: fourCC("othr")
            )
        )
        XCTAssertFalse(
            ScreenCaptureSourceFilter.accepts(
                name: "Studio Display Camera",
                manufacturer: "Apple Inc.",
                modelID: "Studio Display",
                isContinuityCamera: false,
                transportType: fourCC("usb ")
            )
        )
    }

    func testRejectsWirelessMobileScreenSources() {
        XCTAssertFalse(
            ScreenCaptureSourceFilter.accepts(
                name: "Vivi 的 iPhone",
                manufacturer: "Apple Inc.",
                modelID: "iPhone17,1",
                isContinuityCamera: false,
                transportType: fourCC("wrls")
            )
        )
    }

    func testClassifiesPublicTransportTypes() {
        XCTAssertEqual(
            ScreenCaptureSourceFilter.connectionKind(transportType: fourCC("usb ")),
            .wired
        )
        for transport in ["wrls", "ntwk", "blue"] {
            XCTAssertEqual(
                ScreenCaptureSourceFilter.connectionKind(transportType: fourCC(transport)),
                .wireless
            )
        }
        XCTAssertEqual(
            ScreenCaptureSourceFilter.connectionKind(transportType: fourCC("virt")),
            .unknown
        )
    }

    private func fourCC(_ value: String) -> Int32 {
        value.utf8.reduce(Int32(0)) { ($0 << 8) | Int32($1) }
    }
}
