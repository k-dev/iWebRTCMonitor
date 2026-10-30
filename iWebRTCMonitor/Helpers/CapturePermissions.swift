import AVFoundation

/// Checks capture permissions before a monitor session creates its media resources.
/// Injectable operations let tests exercise permission changes without system prompts.
@MainActor
struct CapturePermissions {
    enum Resource: CaseIterable {
        case camera
        case microphone

        var mediaType: AVMediaType { self == .camera ? .video : .audio }
        var name: String { self == .camera ? "Camera" : "Microphone" }
    }

    struct Failure: Equatable {
        let resource: Resource
        let isRestricted: Bool

        var title: String { "\(resource.name) access required" }

        var message: String {
            if isRestricted {
                return "\(resource.name) access is restricted by system policy. Check device restrictions or contact your administrator before trying again."
            }
#if os(macOS)
            return "Allow access in System Settings → Privacy & Security → \(resource.name), then try again. Camera mode requires both camera and microphone access."
#else
            return "Allow \(resource.name.lowercased()) access in Settings → Privacy & Security → \(resource.name), then try again. Camera mode requires both camera and microphone access."
#endif
        }
    }

    var authorizationStatus: (AVMediaType) -> AVAuthorizationStatus = {
        AVCaptureDevice.authorizationStatus(for: $0)
    }
    var requestAccess: (AVMediaType) async -> Bool = {
        await AVCaptureDevice.requestAccess(for: $0)
    }

    func check() async -> Failure? {
        for resource in Resource.allCases {
            switch authorizationStatus(resource.mediaType) {
            case .authorized:
                continue
            case .notDetermined:
                if await requestAccess(resource.mediaType) { continue }
                return Failure(resource: resource,
                               isRestricted: authorizationStatus(resource.mediaType) == .restricted)
            case .restricted:
                return Failure(resource: resource, isRestricted: true)
            case .denied:
                return Failure(resource: resource, isRestricted: false)
            @unknown default:
                return Failure(resource: resource, isRestricted: true)
            }
        }
        return nil
    }
}
