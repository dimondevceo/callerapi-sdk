# CocoaPods spec for the iOS 18+ Live Caller ID Lookup integration.
#
# Swift Package Manager (Package.swift) is the primary channel; this spec exists
# because a large share of enterprise iOS apps — and every React Native app — are
# still CocoaPods-based and cannot consume a SwiftPM package. Both point at the
# same git tag, so there is exactly one release artifact per version.
#
#   pod 'CallerAPILiveCallerID', '~> 1.2'
#
# Every path below is relative to THIS directory, which is also the root of the
# public github.com/dimondevceo/callerapi-sdk mirror that customers resolve from
# (see sdk/scripts/build-ios-mirror.sh). That is what lets `pod lib lint` here
# validate exactly what `pod install` will produce; repo-root-relative paths
# would lint clean under --quick and then ship a pod with no sources in it.
Pod::Spec.new do |s|
  s.name         = 'CallerAPILiveCallerID'
  s.version      = '1.6.0'
  s.summary      = 'iOS 18+ Live Caller ID Lookup integration for CallerAPI.'
  s.description  = <<~DESC
    Participates in Apple's Live Caller ID Lookup: the system privately queries
    the CallerAPI backend on every incoming call using Oblivious HTTP, Privacy
    Pass and keyword PIR. This package supplies the extension context (service
    URL, token issuer URL, per-user tier token) plus host-app helpers for
    enabling the extension, prewarming PIR parameters, and the metering
    heartbeat used for MAU accounting.
  DESC
  s.homepage     = 'https://callerapi.com'
  s.license      = { :type => 'Commercial', :file => 'LICENSE' }
  s.author       = { 'CallerAPI' => 'support@callerapi.com' }
  s.source       = {
    :git => 'https://github.com/dimondevceo/callerapi-sdk.git',
    # Bare version tags in the mirror, so SwiftPM's `from: "1.2.0"` and
    # CocoaPods resolve the same commit.
    :tag => s.version.to_s
  }

  s.platform              = :ios, '18.0'
  s.swift_versions        = ['5.9']
  s.source_files          = 'Sources/CallerAPILiveCallerID/**/*.swift'
  s.resource_bundles      = {
    'CallerAPILiveCallerID' => ['Sources/CallerAPILiveCallerID/PrivacyInfo.xcprivacy']
  }
  # DeviceCheck supplies App Attest (AppAttest.swift). Swift autolinks frameworks
  # it imports, but CocoaPods-generated targets do not always honour that for a
  # static library, and the failure mode is an undefined-symbol link error in the
  # customer's app rather than here — so it is declared explicitly.
  s.frameworks            = 'Foundation', 'UIKit', 'IdentityLookup', 'BackgroundTasks',
                            'DeviceCheck', 'CryptoKit', 'CallKit'
end
