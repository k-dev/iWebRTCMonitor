#if os(macOS)
import AVFoundation
import CoreImage.CIFilterBuiltins
import XCTest
@testable import iWebRTCMonitor

@MainActor
final class QRScannerTests: XCTestCase {
    func testBackgroundFramesDeliverQRCodeOnceOnMainActor() async {
        let payload = "com.example.monitor://join?roomID=qr-scanner-regression"
        let decoded = expectation(description: "QR payload decoded")
        decoded.assertForOverFulfill = true
        let drained = expectation(description: "Frame callbacks drained")
        var received: [String] = []
        let coordinator = QRScannerViewCoordinator { value in
            MainActor.assertIsolated()
            received.append(value)
            decoded.fulfill()
        }

        DispatchQueue(label: "qrScanner.test.frames").async {
            dispatchPrecondition(condition: .notOnQueue(.main))
            do {
                let sample = try Self.makeFrame(payload: payload)
                let output = AVCaptureVideoDataOutput()
                let connection = AVCaptureConnection(inputPorts: [], output: output)
                // Exercise the delegate witness used by AVFoundation, including repeated frames.
                let delegate: AVCaptureVideoDataOutputSampleBufferDelegate = coordinator
                delegate.captureOutput?(output, didOutput: sample, from: connection)
                delegate.captureOutput?(output, didOutput: sample, from: connection)
            } catch {
                XCTFail("Could not create QR frame: \(error)")
            }
            DispatchQueue.main.async { drained.fulfill() }
        }

        await fulfillment(of: [decoded, drained], timeout: 15)
        XCTAssertEqual(received, [payload])
    }

    func testBlankFrameDoesNotConsumeScanCallback() async {
        let payload = "com.example.monitor://join?roomID=after-blank-frame"
        let decoded = expectation(description: "Valid frame after blank frame")
        let drained = expectation(description: "Frame callbacks drained")
        var received: [String] = []
        let coordinator = QRScannerViewCoordinator { value in
            MainActor.assertIsolated()
            received.append(value)
            decoded.fulfill()
        }

        DispatchQueue(label: "qrScanner.test.frames").async {
            do {
                let output = AVCaptureVideoDataOutput()
                let connection = AVCaptureConnection(inputPorts: [], output: output)
                let delegate: AVCaptureVideoDataOutputSampleBufferDelegate = coordinator
                delegate.captureOutput?(output, didOutput: try Self.makeFrame(payload: nil), from: connection)
                delegate.captureOutput?(output, didOutput: try Self.makeFrame(payload: payload), from: connection)
            } catch {
                XCTFail("Could not create test frames: \(error)")
            }
            DispatchQueue.main.async { drained.fulfill() }
        }

        await fulfillment(of: [decoded, drained], timeout: 15)
        XCTAssertEqual(received, [payload])
    }

    nonisolated private static func makeFrame(payload: String?) throws -> CMSampleBuffer {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 640)
        var image = CIImage(color: .white).cropped(to: bounds)
        if let payload {
            let generator = CIFilter.qrCodeGenerator()
            generator.message = Data(payload.utf8)
            let qr = try XCTUnwrap(generator.outputImage)
                .transformed(by: CGAffineTransform(scaleX: 8, y: 8))
            let centered = qr.transformed(by: CGAffineTransform(
                translationX: (bounds.width - qr.extent.width) / 2,
                y: (bounds.height - qr.extent.height) / 2))
            image = centered.composited(over: image)
        }

        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 640, 640,
                                           kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)
        CIContext(options: [.useSoftwareRenderer: true]).render(image, to: pixelBuffer,
                                                                bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                                    imageBuffer: pixelBuffer,
                                                                    formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                               imageBuffer: pixelBuffer,
                                                               formatDescription: try XCTUnwrap(format),
                                                               sampleTiming: &timing, sampleBufferOut: &sample), noErr)
        return try XCTUnwrap(sample)
    }
}
#endif
