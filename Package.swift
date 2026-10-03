// swift-tools-version: 6.0
import PackageDescription

let package = Package(
   name: "SpecQR",
   platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9)],
   products: [
      .library(name: "SpecQR", targets: ["SpecQR"]),
      .executable(name: "specqr-cli", targets: ["specqr-cli"]),
   ],
   targets: [
      .target(name: "SpecQR"),
      .executableTarget(name: "specqr-cli", dependencies: ["SpecQR"]),
      .testTarget(name: "SpecQRTests", dependencies: ["SpecQR"], resources: [.copy("Fixtures")]),
   ]
)
