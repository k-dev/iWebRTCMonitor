import AVFoundation
import Testing
@testable import iWebRTCMonitor

@MainActor
struct CapturePermissionsTests {
    @Test
    func authorizedPermissionsDoNotPrompt() async {
        let permissions = CapturePermissions(authorizationStatus: { _ in .authorized }, requestAccess: { _ in
            Issue.record("An authorized permission must not prompt again")
            return false
        })
        #expect(await permissions.check() == nil)
    }

    @Test
    func requestsCameraThenMicrophone() async {
        var requests: [AVMediaType] = []
        let permissions = CapturePermissions(authorizationStatus: { _ in .notDetermined }, requestAccess: {
            requests.append($0)
            return true
        })
        #expect(await permissions.check() == nil)
        #expect(requests == [.video, .audio])
    }

    @Test(arguments: [CapturePermissions.Resource.camera, .microphone])
    func deniedPromptIdentifiesResource(resource: CapturePermissions.Resource) async {
        var requests: [AVMediaType] = []
        let permissions = CapturePermissions(authorizationStatus: { _ in .notDetermined }, requestAccess: {
            requests.append($0)
            return $0 != resource.mediaType
        })
        #expect(await permissions.check() == .init(resource: resource, isRestricted: false))
        #expect(requests == (resource == .camera ? [.video] : [.video, .audio]))
    }

    @Test(arguments: [CapturePermissions.Resource.camera, .microphone], [false, true])
    func existingDenialDoesNotPrompt(resource: CapturePermissions.Resource, restricted: Bool) async {
        let permissions = CapturePermissions(authorizationStatus: {
            $0 == resource.mediaType ? (restricted ? .restricted : .denied) : .authorized
        }, requestAccess: { _ in
            Issue.record("Denied or restricted permissions must not prompt again")
            return true
        })
        #expect(await permissions.check() == .init(resource: resource, isRestricted: restricted))
    }

    @Test
    func rechecksAfterSettingsChange() async {
        var status = AVAuthorizationStatus.denied
        let permissions = CapturePermissions(authorizationStatus: { _ in status }, requestAccess: { _ in false })
        #expect(await permissions.check() != nil)
        status = .authorized
        #expect(await permissions.check() == nil)
    }

    @Test
    func roomLeavesPendingAndRetriesPermissions() async {
        var cameraAllowed = false
        let permissions = CapturePermissions(authorizationStatus: {
            $0 == .video && cameraAllowed ? .authorized : .denied
        }, requestAccess: { _ in false })
        let model = RoomViewModel(roomID: "permission-test", urlString: "ws://127.0.0.1:1",
                                  role: .monitor, permissions: permissions)
        await model.setup()
        #expect(model.state == .permissionRequired)
        #expect(model.permissionFailure?.resource == .camera)
        #expect(model.localVideoTrack == nil)

        cameraAllowed = true
        await model.setup()
        #expect(model.state == .permissionRequired)
        #expect(model.permissionFailure?.resource == .microphone)
        #expect(model.localVideoTrack == nil)
    }
}
