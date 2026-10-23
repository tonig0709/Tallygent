// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexQuotaWidget",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexQuotaCore", targets: ["CodexQuotaCore"]),
        .executable(name: "quota-self-check", targets: ["QuotaSelfCheck"])
    ],
    targets: [
        .target(
            name: "CodexQuotaCore",
            path: "Shared"
        ),
        .executableTarget(
            name: "QuotaSelfCheck",
            dependencies: ["CodexQuotaCore"],
            path: "Checks"
        )
    ]
)
