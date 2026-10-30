import AVFoundation

extension CapturePermissions {
    /// Composition point for the Camera screen. Release builds always use system permissions.
    static func forCameraScreen() -> CapturePermissions {
#if DEBUG
        guard let scenario = ProcessInfo.processInfo.environment["UITEST_CAPTURE_PERMISSIONS"] else {
            return CapturePermissions()
        }
        var cameraChecks = 0
        switch scenario {
        case "camera-denied", "microphone-denied", "camera-restricted", "microphone-restricted", "retry":
            return CapturePermissions(authorizationStatus: { media in
                if scenario == "retry" {
                    if media == .video {
                        cameraChecks += 1
                        return cameraChecks == 1 ? .denied : .authorized
                    }
                    return .denied
                }
                let blockedMedia: AVMediaType = scenario.hasPrefix("camera") ? .video : .audio
                guard media == blockedMedia else { return .authorized }
                return scenario.hasSuffix("restricted") ? .restricted : .denied
            }, requestAccess: { _ in false })
        default:
            return CapturePermissions()
        }
#else
        return CapturePermissions()
#endif
    }
}
