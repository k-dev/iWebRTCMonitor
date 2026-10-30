//
//  WebRTCLocal.swift
//  iWebRTCMonitor
//  SPDX-License-Identifier: GPL-3.0-or-later OR LicenseRef-Commercial. See LICENSE.txt
//  Copyright 2026 (c) Kyrylo
//  Created by Kyrylo on 04.07.2026.
//

import WebRTC
@preconcurrency import AVFoundation

/// Owns the local WebRTC factory, tracks, and camera capturer for one session.
///
/// `SessionManager` creates and releases this object. All peer clients share its
/// factory and local tracks. The session queue starts configuration work. Camera
/// start work moves to the main queue.
/// This type does not provide independent synchronization for its mutable state.
final class WebRTCLocalMedia: NSObject, @unchecked Sendable {

    private var videoCapturer: RTCCameraVideoCapturer?
    private(set) var factory: RTCPeerConnectionFactory
    private(set) var currentDevice: AVCaptureDevice?
    private(set) var currentH264Levels: [String]?
    private var pendingH264Levels: [String]?
    lazy private(set) var captureDevices: [AVCaptureDevice] = availableCaptureDevices()
    
    var localAudioTrack: RTCAudioTrack?
    var localVideoTrack: RTCVideoTrack?
    var onVideoCaptureStarted: ((RTCVideoTrack) -> Void)?
    
    init(factory: RTCPeerConnectionFactory? = nil) {
//        let watchdogFactory = WatchdogVideoEncoderFactory(over: TrackingVideoEncoderFactory())
//        self.factory = factory ?? RTCPeerConnectionFactory(encoderFactory: TrackingVideoEncoderFactory(),
        self.factory = factory ?? RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(),
                                                           decoderFactory: RTCDefaultVideoDecoderFactory())
        super.init()
        
//        watchdogFactory.onEncoderFailure = { [weak self] in
//           Log(level: .error, "!Detected pre-failure condition!")
//           self?.stop()
//           if let currentDevice = self?.currentDevice {
//               let levels = self?.currentH264Levels
//               self?.currentDevice = nil
//               self?.currentH264Levels = nil
//               self?.switchCapturing(to: currentDevice, matching: levels)
//           }
//       }

        Log(level: .debug, "Default video encoder codecs", RTCDefaultVideoEncoderFactory().localH264Capabilities())
    }
    
    /// Creates the shared local audio track when the platform supports it.
    func prepareAudioTrack() {
#if !targetEnvironment(simulator)
        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        let audioSource = factory.audioSource(with: audioConstraints)
        localAudioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
#endif
    }
    
    /// Creates the shared local video track and begins the first camera capture.
    func prepareVideoTrackIfNeeded() {
        guard videoCapturer == nil else {
            Log(level: .debug, "Video capturer is already inited")
            return
        }

        let videoSource = factory.videoSource()
        videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        localVideoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        if let device = captureDevices.first {
            let fps = 60.0
            let size = CGSize(width: 3600, height: 2400)
            let (format, maxFps) = device.compatibleVideoOutputFormat(for: videoCapturer?.captureSession,
                                                                      size: size,
                                                                      fps: fps)
            if let format {
                DispatchQueue.main.async { [weak self] in
                    self?.startVideoCapture(with: self?.videoCapturer, device: device, format: format, fps: maxFps)
                }
            }
            else {
                Log(level: .error, "Failed to calculate format")
            }
        }
    }
    
    func stop() {
        videoCapturer?.stopCapture()
    }
    
    func updateCapturing(for peerConnection: RTCPeerConnection) {
        Log(level: .status, "Updating capturing for peerConnection")
        
        if peerConnection.senders.contains(where: { $0.track?.kind == kRTCMediaStreamTrackKindVideo }) == false {
            Log(level: .verbose, "No video sender")
        }

        guard let remoteSDP = peerConnection.remoteDescription else {
            Log(level: .verbose, "No remote description")
            return
        }
        
        updateCapturing(for: remoteSDP.negotiatedLevels())
    }
    
    func updateCapturing(for levels: [String]) {
        Log(level: .status, "Updating capturing for levels", levels)
        
        if let currentDevice {
            switchCapturing(to: currentDevice, matching: levels.count > 0 ? levels : nil)
        }
        else {
            pendingH264Levels = levels
            Log(level: .verbose, "Pending levels", levels)
        }
    }
    
    private func availableCaptureDevices() -> [AVCaptureDevice] {
        var devices: [AVCaptureDevice] = []
#if os(macOS)
        if let device = AVCaptureDevice.default(for: .video) {
            devices = [ device ]
        }
#else
        let types: [AVCaptureDevice.DeviceType] = [ .builtInTelephotoCamera,
                                                    .builtInUltraWideCamera,
                                                    .builtInWideAngleCamera ]
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
        devices = discoverySession.devices
#endif
        return devices
    }
    
    /// Selects a device and capture format for the shared local video track.
    func switchCapturing(to device: AVCaptureDevice, matching newLevels: [String]? = nil) {
        guard captureDevices.contains(device) else {
            Log(level: .warning, "Trying to capture with device not in list")
            return
        }
        
        let levels = newLevels ?? pendingH264Levels ?? currentH264Levels
        
        guard device != currentDevice || levels != currentH264Levels else {
            Log(level: .status, "Trying to switch to the same device. Skipping")
            return
        }
        
        if currentDevice != nil {
            stop()
            currentDevice = nil
        }

        let bestSize = CGSize(width: 3600, height: 2400)
        let bestFps = 60.0
        
        var videoSize = bestSize
        var videoFps = bestFps

        if let levels {
            var lastSize = CGSize.zero
            var lastFps = 0.0
            
            for level in levels {
                let (outSize, fps) = H264Levels.videoFormat(for: level, desiredSize: bestSize, minFps: 10)
                if outSize.width > lastSize.width {
                    lastSize = outSize
                    lastFps = fps
                    debugPrint(#function, "Updating", outSize, fps)
                }
                else {
                    debugPrint(#function, "Skipping", outSize, fps)
                }
            }
            videoSize = lastSize
            videoFps = lastFps
        }

        Log(level: .debug, "Pre-compatibleVideoOutputFormat", videoSize, videoFps)
        let (format, fps) = device.compatibleVideoOutputFormat(for: videoCapturer?.captureSession,
                                                               size: videoSize,
                                                               fps: videoFps)
        Log(level: .debug, "After compatibleVideoOutputFormat", format ?? "<null>", fps)
        
        guard let format else {
            Log(level: .error, "Failed to define best format")
            return
        }
        
        currentH264Levels = levels
        pendingH264Levels = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.startVideoCapture(with: self?.videoCapturer, device: device, format: format, fps: fps)
        }
    }
    
    private func startVideoCapture(with capturer: RTCCameraVideoCapturer?,
                                   device: AVCaptureDevice,
                                   format: AVCaptureDevice.Format,
                                   fps: Double) {
        Log(level: .status, "Starting capture with", device.localizedName, format, fps)

        guard let capturer else {
            Log(level: .error, "No Video capturer")
            return
        }
        
#if os(macOS)
        let iFPS = 0
#else
        let iFPS = Int(fps)
#endif
        
        capturer.startCapture(with: device, format: format, fps: iFPS) { [weak self] error in
            if let error = error {
                Log(level: .error, "Failed to start camera: \(error.localizedDescription)")
            }
            else {
                Log(level: .status, "Camera capture started successfully")
                self?.currentDevice = device
                if let track = self?.localVideoTrack {
                    self?.onVideoCaptureStarted?(track)
                }
                else {
                    Log(level: .warning, "Unexpected: NO video track")
                }
            }
        }
    }
}
