enum MicrophonePermissionState: Equatable, Sendable {
  case notRequested
  case granted
  case denied
  case restricted

  var title: String {
    switch self {
    case .notRequested: "Not requested"
    case .granted: "Granted"
    case .denied: "Denied"
    case .restricted: "Restricted"
    }
  }
}
