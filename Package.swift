// swift-tools-version:5.9
import PackageDescription

// The public CallerAPI iOS package.
//
// This manifest is the ROOT of github.com/dimondevceo/callerapi-sdk, the public
// mirror customers resolve from. It is assembled by sdk/scripts/build-ios-mirror.sh
// from two directories in the private monorepo — sdk/ios (the core SDK) and
// sdk/ios-lcid (Live Caller ID Lookup) — because SwiftPM requires Package.swift at
// a repository root and neither of those is one.
//
// Two products, one tag:
//
//   • CallerAPI — spam detection, caller labels, and the CallKit Call Directory
//     blocklist. Works from iOS 13. A Swift wrapper over a prebuilt, self-contained
//     xcframework that statically bundles libcurl and mbedTLS (iOS ships no libcurl),
//     so the only system dependency is zlib.
//
//   • CallerAPILiveCallerID — Apple's iOS 18 Live Caller ID Lookup, where the system
//     itself queries the backend on every incoming call over Oblivious HTTP with
//     Privacy Pass and keyword PIR. Additive: most apps take both.
//
// Shipping them together means one package to add and one version to track. The
// platform floor is iOS 13 so the core stays usable on older devices; every iOS 18
// API in the Live Caller ID target is behind `@available`, which the compiler
// enforces at this deployment target.
let package = Package(
    name: "CallerAPI",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "CallerAPI", targets: ["CallerAPI"]),
        .library(name: "CallerAPILiveCallerID", targets: ["CallerAPILiveCallerID"]),
    ],
    targets: [
        .target(
            name: "CallerAPI",
            dependencies: ["CallerAPICCore"],
            path: "Sources/CallerAPI",
            exclude: ["Bridge.h"],
            linkerSettings: [
                // zlib (gzip transfer-encoding) comes from the iOS SDK. curl and
                // mbedTLS are already inside the xcframework, so they are not here.
                .linkedLibrary("z"),
            ]
        ),
        // Prebuilt C core with a module map, so the Swift sources above can
        // `import CallerAPICCore`.
        .binaryTarget(
            name: "CallerAPICCore",
            path: "CallerAPI.xcframework"
        ),
        .target(
            name: "CallerAPILiveCallerID",
            path: "Sources/CallerAPILiveCallerID",
            // Apple's required privacy manifest, embedded so App Store privacy
            // report tooling picks it up.
            resources: [
                .copy("PrivacyInfo.xcprivacy"),
            ],
            // LiveCallerIDLookupManager reaches the system through the XPC
            // service inside CallKit.framework/XPCServices, and an XPCService
            // name resolves only against the frameworks loaded in the process.
            // A host that links this library but never loads CallKit fails
            // every call with `bootstrap look-up: xpc_error=[3: No such
            // process]`, surfaced as Cocoa 4099, before a single request is
            // sent. `import CallKit` alone autolinks only the Swift overlay,
            // and weakly, so the framework is named here.
            //
            // This has to stay in step with ios-lcid/Package.swift. The two
            // manifests are separate files: that one builds the standalone
            // package, this one is the root of the public mirror, and it is
            // the mirror customers resolve. Fixing only the standalone one
            // ships the bug.
            linkerSettings: [
                .linkedFramework("CallKit", .when(platforms: [.iOS])),
            ]
        ),
        // The Foundation-only configuration and token-sharing logic. The
        // IdentityLookup-backed call-time surface is compiled under `#if os(iOS)`,
        // so these run on a Mac; the call screen itself needs a real iOS 18 device.
        .testTarget(
            name: "CallerAPILiveCallerIDTests",
            dependencies: ["CallerAPILiveCallerID"],
            path: "Tests/CallerAPILiveCallerIDTests"
        ),
    ]
)
