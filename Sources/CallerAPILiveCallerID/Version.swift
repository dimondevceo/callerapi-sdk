import Foundation

@available(iOS 18.0, *)
public extension CallerAPILiveCallerID {
    /// The released SDK version, as a semantic-version string.
    ///
    /// Single source of truth: `sdk/VERSION`, enforced by
    /// `sdk/scripts/check-sdk-versions.sh`. It must equal the git tag cut for the
    /// release and the server's `LCID_LATEST_SDK_VERSION`, and it is reported as
    /// `sdk_version` on the metering heartbeat — which is how a customer's build
    /// is identified in a support ticket, since the call-time lookup itself is
    /// run by iOS and is otherwise opaque to the host app.
    static let sdkVersion = "1.5.0"
}
