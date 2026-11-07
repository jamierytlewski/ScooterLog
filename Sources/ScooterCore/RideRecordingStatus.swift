public enum RideRecordingStatus: Equatable, Sendable {
    case recording, paused, remoteRecording, remotePaused, remoteOffline

    public init(isRemote: Bool, isRecording: Bool, isReachable: Bool) {
        if isRemote {
            self = !isReachable ? .remoteOffline : (isRecording ? .remoteRecording : .remotePaused)
        } else {
            self = isRecording ? .recording : .paused
        }
    }
}
