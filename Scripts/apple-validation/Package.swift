// swift-tools-version: 6.0
import PackageDescription

let package = Package(
   name: "SpecQRAppleValidation",
   platforms: [.macOS(.v14)],
   dependencies: [.package(name: "SpecQR", path: "../..")],
   targets: [
      .testTarget(
         name: "SpecQRAppleValidationTests",
         dependencies: [.product(name: "SpecQR", package: "SpecQR")])
   ]
)
