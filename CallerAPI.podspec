# CocoaPods spec for the CallerAPI core iOS SDK.
#
# Swift Package Manager (Package.swift, alongside this file) is the primary
# channel. This spec exists because a large share of enterprise iOS apps — and
# every React Native and Flutter app — are CocoaPods-based and cannot consume a
# SwiftPM package. Both point at the same git tag, so there is exactly one
# release artifact per version.
#
#   pod 'CallerAPI', '~> 1.3'
#
# The React Native and Flutter wrappers declare this as a dependency rather than
# vendoring their own copy of the xcframework, which is what keeps a `pub add` or
# `npm install` from having to carry 6.7 MB of binary per ecosystem.
#
# Paths are relative to the root of the public github.com/dimondevceo/callerapi-sdk
# mirror (see sdk/scripts/build-ios-mirror.sh), which is where this file lands.
Pod::Spec.new do |s|
  s.name         = 'CallerAPI'
  s.version      = '1.3.1'
  s.summary      = 'Privacy-preserving spam detection and caller labels for iOS.'
  s.description  = <<~DESC
    Caller identification and spam detection with a k-anonymity lookup protocol:
    the device reveals only a short hash prefix, never the number being looked
    up. Includes the CallKit Call Directory blocklist path used to block spam on
    iOS 13-17, where the system allows no per-call network lookup.

    For iOS 18's system-level Live Caller ID Lookup, add the
    CallerAPILiveCallerID pod as well — the two are additive.
  DESC
  s.homepage     = 'https://callerapi.com'
  s.license      = { :type => 'Commercial', :file => 'LICENSE' }
  s.author       = { 'CallerAPI' => 'support@callerapi.com' }
  s.source       = {
    :git => 'https://github.com/dimondevceo/callerapi-sdk.git',
    # Bare version tags in the mirror, so SwiftPM's `from: "1.3.1"` and CocoaPods
    # resolve the same commit.
    :tag => s.version.to_s
  }

  s.platform              = :ios, '13.0'
  s.swift_versions        = ['5.9']
  s.source_files          = 'Sources/CallerAPI/**/*.swift'
  # Self-contained: libcurl and mbedTLS are statically inside the xcframework,
  # because iOS ships no libcurl. zlib is the only system library needed.
  s.vendored_frameworks   = 'CallerAPI.xcframework'
  s.libraries             = 'z'
  s.frameworks            = 'Foundation', 'CallKit', 'BackgroundTasks', 'Security'

  # The xcframework carries a static library plus a module map declaring
  # `CallerAPICCore`. CocoaPods does not wire a module map from inside a vendored
  # static xcframework into the Swift compile, so it is passed explicitly. Without
  # it the `import CallerAPICCore` in Sources/CallerAPI fails to resolve and every
  # call into the C core is an undefined symbol.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_SWIFT_FLAGS' => '$(inherited) -Xcc ' \
      '-fmodule-map-file="${PODS_XCFRAMEWORKS_BUILD_DIR}/CallerAPI/Headers/module.modulemap"',
  }
end
