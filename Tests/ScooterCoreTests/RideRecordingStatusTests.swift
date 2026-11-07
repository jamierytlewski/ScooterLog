import Testing
@testable import ScooterCore

@Suite
struct RideRecordingStatusTests {
    @Test func localStatusDoesNotDependOnCompanionReachability() {
        for reachable in [false, true] {
            #expect(RideRecordingStatus(isRemote: false, isRecording: true, isReachable: reachable) == .recording)
            #expect(RideRecordingStatus(isRemote: false, isRecording: false, isReachable: reachable) == .paused)
        }
    }

    @Test func reachableCompanionReportsItsRecordingState() {
        #expect(RideRecordingStatus(isRemote: true, isRecording: true, isReachable: true) == .remoteRecording)
        #expect(RideRecordingStatus(isRemote: true, isRecording: false, isReachable: true) == .remotePaused)
    }

    @Test func offlineCompanionDoesNotClaimCurrentRecordingState() {
        for recording in [false, true] {
            #expect(RideRecordingStatus(isRemote: true, isRecording: recording, isReachable: false) == .remoteOffline)
        }
    }
}
