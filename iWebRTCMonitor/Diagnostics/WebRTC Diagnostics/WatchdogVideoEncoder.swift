//
//  WatchdogVideoEncoder.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Created by Kyrylo on 13.07.2026.
//

import WebRTC

/// Wraps a native encoder and reports repeated encode failures.
///
/// The WebRTC encoder factory creates this type when the optional watchdog
/// factory is in use. WebRTC controls calls to encoder methods. This wrapper
/// does not add synchronization around its mutable failure count.
final class WatchdogVideoEncoder: NSObject, RTCVideoEncoder, @unchecked Sendable {
    
    // MARK: - RTCVideoEncoder extension
    func encode(_ frame: RTCVideoFrame, codecSpecificInfo info: (any RTCCodecSpecificInfo)?, frameTypes: [NSNumber]) -> Int {
        let result = wrapped.encode(frame, codecSpecificInfo: info, frameTypes: frameTypes)
        if result != 0 {
            consecutiveFailures += 1
            if consecutiveFailures >= failureThreshold {
                consecutiveFailures = 0
                DispatchQueue.main.async { [weak self] in self?.onRepeatedFailure() }
            }
        } else {
            consecutiveFailures = 0
        }
        return result
    }
    
    func setCallback(_ callback: RTCVideoEncoderCallback?) {
        wrapped.setCallback(callback)
    }
    
    func startEncode(with settings: RTCVideoEncoderSettings, numberOfCores: Int32) -> Int {
        let result = wrapped.startEncode(with: settings, numberOfCores: numberOfCores)
        if result != 0 {
            debugPrint("!Detected pre-failure condition!")
        }
        return result
    }
    
    func release() -> Int {
        return wrapped.release()
    }
    
    func setBitrate(_ bitrateKbit: UInt32, framerate: UInt32) -> Int32 {
        return wrapped.setBitrate(bitrateKbit, framerate: framerate)
    }
    
    func implementationName() -> String {
        "Watchdog wrapper"
    }
    
    func scalingSettings() -> RTCVideoEncoderQpThresholds? {
        wrapped.scalingSettings()
    }
    
    let resolutionAlignment: Int
    
    let applyAlignmentToAllSimulcastLayers: Bool
    
    let supportsNativeHandle: Bool
    
    // MARK: - Watchdog wrapping
    private let wrapped: RTCVideoEncoder
    private let onRepeatedFailure: () -> Void
    private var consecutiveFailures = 0
    private let failureThreshold = 3   // ignore a single transient failure, act on a streak

    init(wrapping encoder: RTCVideoEncoder, onRepeatedFailure: @escaping () -> Void) {
        self.wrapped = encoder
        self.onRepeatedFailure = onRepeatedFailure

        self.resolutionAlignment = wrapped.resolutionAlignment
        self.applyAlignmentToAllSimulcastLayers = wrapped.applyAlignmentToAllSimulcastLayers
        self.supportsNativeHandle = wrapped.supportsNativeHandle

        super.init()
    }
}

/// Creates watchdog-wrapped encoders from one native encoder factory.
final class WatchdogVideoEncoderFactory: NSObject, RTCVideoEncoderFactory {

    let innerFactory: RTCVideoEncoderFactory
    var onEncoderFailure: (() -> Void)?

    init(over factory: RTCVideoEncoderFactory? = nil, onEncoderFailure: (() -> Void)? = nil) {
        self.innerFactory = factory ?? RTCDefaultVideoEncoderFactory()
        self.onEncoderFailure = onEncoderFailure
        super.init()
    }
    
    // MARK: - RTCVideoEncoderFactory
    func createEncoder(_ info: RTCVideoCodecInfo) -> RTCVideoEncoder? {
        guard let encoder = innerFactory.createEncoder(info) else {
            return nil
        }
        return WatchdogVideoEncoder(wrapping: encoder) { [weak self] in
            self?.onEncoderFailure?()
        }
    }

    func supportedCodecs() -> [RTCVideoCodecInfo] {
        innerFactory.supportedCodecs()
    }
}
