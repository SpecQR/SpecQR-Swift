// swift-tools-version: 6.0
import PackageDescription

let package = Package(
   name: "SpecQRDemo",
   platforms: [.macOS(.v13)],
   dependencies: [.package(name: "SpecQR", path: "../..")],
   targets: [
      .executableTarget(name: "SpecQRDemo", dependencies: [.product(name: "SpecQR", package: "SpecQR")])
   ]
)
