// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "FreeFlow",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "FreeFlow", targets: ["FreeFlow"]),
    .library(name: "FreeFlowCore", targets: ["FreeFlowCore"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/FluidInference/FluidAudio.git",
      exact: "0.15.5"
    )
  ],
  targets: [
    .binaryTarget(
      name: "WhisperFramework",
      url:
        "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.1/whisper-v1.9.1-xcframework.zip",
      checksum: "8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c"
    ),
    .target(
      name: "FreeFlowCore"
    ),
    .target(
      name: "FreeFlowCloud"
    ),
    .executableTarget(
      name: "FreeFlow",
      dependencies: [
        "FreeFlowCloud",
        "FreeFlowCore",
        "WhisperFramework",
        .product(name: "FluidAudio", package: "FluidAudio"),
      ],
      linkerSettings: [
        .linkedFramework("Accelerate"),
        .linkedFramework("AppKit"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("Carbon"),
        .linkedFramework("CoreML"),
        .linkedFramework("Metal"),
        .linkedFramework("Security"),
      ]
    ),
    .testTarget(
      name: "FreeFlowCoreTests",
      dependencies: ["FreeFlowCore"]
    ),
    .testTarget(
      name: "FreeFlowCloudTests",
      dependencies: ["FreeFlowCloud"]
    ),
  ]
)
