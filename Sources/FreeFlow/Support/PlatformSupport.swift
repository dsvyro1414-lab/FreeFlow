enum PlatformSupport {
  #if arch(arm64)
    static let supportsParakeet = true
  #else
    static let supportsParakeet = false
  #endif
}
