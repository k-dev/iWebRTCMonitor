//
//  AV+Extensions.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 02.10.2026.
//

import AVFoundation

extension AVCaptureDevice {
    
    func compatibleVideoOutputFormat(for session: AVCaptureSession?, size: CGSize, fps: Double = 10) -> (AVCaptureDevice.Format?, Double) {
        Log(level: .verbose, #function)
        
        var bestFormat: AVCaptureDevice.Format? = nil
        var outFPS: Double = fps
        
        let targetArea = Int(size.width * size.height)
        
        for format in formats {
            Log(level: .debug, "Working on \(format)")
            
            guard format.isWebRTCCompatible else {
                Log(level: .debug, "Skipping as not WebRTCCompatible")
                continue
            }
            
            let fd = format.formatDescription
            let formatArea = Int(fd.width * fd.height)
            
            if formatArea > targetArea {
                continue
            }
            
            guard var bestFrameRange = format.videoSupportedFrameRateRanges.first else {
                continue
            }

            for range in format.videoSupportedFrameRateRanges {
                if range.minFrameRate <= fps && bestFrameRange.maxFrameRate <= range.maxFrameRate {
                    bestFrameRange = range
                }
            }
            
            outFPS = min(fps, bestFrameRange.maxFrameRate)

            if let bestFormat, bestFormat.formatDescription > format.formatDescription {
                continue
            }

            Log(level: .debug, "Choosing as another bestFormat")
            bestFormat = format
        }
        
        return (bestFormat, outFPS)
    }
}

extension AVCaptureSession {
    /// Returns true if this device+format combo would produce a pixel format
    /// AVCaptureVideoDataOutput can actually deliver, avoiding the setVideoSettings crash.
    func isFormatCompatible(device: AVCaptureDevice, format: AVCaptureDevice.Format) -> Bool {
        let captureSession = self
        
        guard let output = captureSession.outputs
            .compactMap({ $0 as? AVCaptureVideoDataOutput })
            .first else { return false }

        // WebRTC's fixed acceptable set (mirrors RTCCVPixelBuffer.supportedPixelFormats):
        let webrtcSupported: Set<OSType> = [
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_32BGRA
        ]

        // Temporarily swap input to the target device to get accurate
        // availableVideoCVPixelFormatTypes for THIS device (mirrors setupVideoDataOutput).
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            return false
        }
        
        guard captureSession.canAddInput(input) else {
            return false
        }

        let previousInputs = captureSession.inputs
        previousInputs.forEach { captureSession.removeInput($0) }
        captureSession.addInput(input)
        
        var didLock = false
        do {
            try device.lockForConfiguration()
            didLock = true
            device.activeFormat = format
        } catch {
            captureSession.removeInput(input)
            previousInputs.forEach { captureSession.addInput($0) }
            return false
        }
        
        let available = Set(output.availableVideoPixelFormatTypes.map { OSType($0) })
        let isCompatible = !available.isDisjoint(with: webrtcSupported)

        // restore original input
        if didLock { device.unlockForConfiguration() }
        captureSession.removeInput(input)
        previousInputs.forEach { captureSession.addInput($0) }

        return isCompatible
    }
}

extension AVCaptureDevice.Format {

    /// Returns true if this format's underlying pixel format is supported by WebRTC.
    var isWebRTCCompatible: Bool {
        // 1. Ensure it's actually a video format
        guard CMFormatDescriptionGetMediaType(formatDescription) == kCMMediaType_Video else {
            return false
        }
        
        // 2. Extract the media subtype (the pixel format type, e.g., '420v', '420f', 'BGRA')
        let pixelFormat = CMFormatDescriptionGetMediaSubType(formatDescription)
        
        // 3. WebRTC's fixed acceptable set
        let webrtcSupported: Set<OSType> = [
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,  // '420f'
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, // '420v'
            kCVPixelFormatType_32BGRA                        // 'BGRA'
        ]
        
        return webrtcSupported.contains(pixelFormat)
    }
}
