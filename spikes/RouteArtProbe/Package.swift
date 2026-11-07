// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProbeArtworkDeletion",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ProbeArtworkDeletion", path: ".", exclude: ["Probe.swift", "Probe.entitlements", "Images", "README.md", "RouteArtProbe.xcodeproj", "DeletionTests", "PrivacyTests", "Benchmarks", "RoutePrivacyProbe.swift"], sources: ["ProbeArtworkDeletion.swift"]),
        .testTarget(name: "ProbeArtworkDeletionTests", dependencies: ["ProbeArtworkDeletion"], path: "DeletionTests"),
        .target(name: "RoutePrivacyProbe", path: ".", exclude: ["Probe.swift", "Probe.entitlements", "Images", "README.md", "RouteArtProbe.xcodeproj", "DeletionTests", "PrivacyTests", "Benchmarks", "ProbeArtworkDeletion.swift"], sources: ["RoutePrivacyProbe.swift"]),
        .testTarget(name: "RoutePrivacyProbeTests", dependencies: ["RoutePrivacyProbe"], path: "PrivacyTests")
    ]
)
