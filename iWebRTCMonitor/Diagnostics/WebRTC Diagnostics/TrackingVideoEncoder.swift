//
//  TrackingVideoEncoder.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Created by Kyrylo on 08.06.2026.
//

import WebRTC

/// Creates diagnostic encoder wrappers that report encoder size changes.
///
/// WebRTC owns calls to the factory and created encoders. The callback has no
/// execution-context guarantee and must transfer UI work to the main actor.
class TrackingVideoEncoderFactory: NSObject, RTCVideoEncoderFactory {
    private let nativeFactory = RTCDefaultVideoEncoderFactory()
    var onResolutionChanged: ((UInt16, UInt16) -> Void)?
    
    func supportedCodecs() -> [RTCVideoCodecInfo] {
        return nativeFactory.supportedCodecs()
    }
    
    func createEncoder(_ info: RTCVideoCodecInfo) -> RTCVideoEncoder? {
        debugPrint(#function)
        guard let nativeEncoder = nativeFactory.createEncoder(info) else { return nil }
        if String(describing: type(of: nativeEncoder)).contains("VP8") {
            // VP8 is not supported by iOS. If factory creates it - we are not wrapping.
            debugPrint("returns VP8: ", String(describing: type(of: nativeEncoder)))
            return nativeEncoder
        }
        // Wrap the native encoder so we can spy on its configuration changes
        return TrackingVideoEncoder(wrappedEncoder: nativeEncoder, onResolutionChanged: onResolutionChanged)
    }
}

/// Forwards encoding to a native encoder and observes its configured size.
class TrackingVideoEncoder: NSObject, RTCVideoEncoder {
    
    func implementationName() -> String {
        return "TrackingVideoEncoder"
    }
    
    func scalingSettings() -> RTCVideoEncoderQpThresholds? {
        wrapped.scalingSettings()
    }
    
    let resolutionAlignment: Int
    
    let applyAlignmentToAllSimulcastLayers: Bool
    
    let supportsNativeHandle: Bool
    
    private let wrapped: RTCVideoEncoder
    var onResolutionChanged: ((UInt16, UInt16) -> Void)?
    
    init(wrappedEncoder: RTCVideoEncoder, onResolutionChanged: ((UInt16, UInt16) -> Void)?) {
        self.wrapped = wrappedEncoder
        self.onResolutionChanged = onResolutionChanged

        self.resolutionAlignment = wrappedEncoder.resolutionAlignment
        self.applyAlignmentToAllSimulcastLayers = wrappedEncoder.applyAlignmentToAllSimulcastLayers
        self.supportsNativeHandle = wrappedEncoder.supportsNativeHandle

        super.init()
    }
    
    func startEncode(with settings: RTCVideoEncoderSettings, numberOfCores: Int32) -> Int {
        // 🎯 Extract exact dynamic dimensions straight from the WebRTC engine reconfig loop
        let currentWidth = settings.width
        let currentHeight = settings.height
        
        Log(level: .verbose, "📹 Encoder reconfigured dynamically to: \(currentWidth)x\(currentHeight)")
        
        onResolutionChanged?(currentWidth, currentHeight)
        
        return wrapped.startEncode(with: settings, numberOfCores: numberOfCores)
    }
    
    func encode(_ frame: RTCVideoFrame, codecSpecificInfo: RTCCodecSpecificInfo?, frameTypes: [NSNumber]) -> Int {
        return wrapped.encode(frame, codecSpecificInfo: codecSpecificInfo, frameTypes: frameTypes)
    }
    
    func release() -> Int {
        return wrapped.release()
    }

    func setCallback(_ callback: RTCVideoEncoderCallback?) {
        wrapped.setCallback(callback)
    }
    
    func setBitrate(_ bitrateKbit: UInt32, framerate: UInt32) -> Int32 {
        return wrapped.setBitrate(bitrateKbit, framerate: framerate)
    }
}
