// Apple App Attest, the iOS half of device attestation.
//
// What it buys us: the SDK credential shipped in a public package is, by
// construction, recoverable by anyone who downloads the app. App Attest makes
// possession of that credential insufficient. The private key is generated inside
// the Secure Enclave and never leaves it, and Apple only certifies keys generated
// by a genuine device running the app whose App ID hash it stamps into the
// attestation. Neither the attestation nor a later assertion can be produced by
// someone who merely extracted the key and secret.
//
// Two-phase, as Apple specifies:
//
//   1. Once per install, generate an enclave key and attest it over a
//      server-issued challenge. The server verifies the certificate chain and
//      records the public key.
//   2. On every heartbeat after that, sign a fresh challenge with the same key.
//      The enclave's signature counter advances each time, so the server can tell
//      a replayed assertion from a new one.
//
// Everything here is best-effort. Attestation runs on the metering path, never on
// the call path, and a device that cannot attest is still reported so the customer
// is billed correctly — whether an unattested device is acceptable is the server's
// decision, not the SDK's.
#if os(iOS)
import Foundation
import CryptoKit
#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// Attestation material to attach to a heartbeat.
@available(iOS 18.0, *)
struct AttestationMaterial {
    /// The server-issued challenge everything below was produced over.
    let challenge: String
    /// Base64 attestation object, present only on the first contact for a key.
    let attestation: String?
    /// Base64 assertion, present on every heartbeat after the key is established.
    let assertion: String?
    /// Base64 key identifier, so the server can find the key on record.
    let keyID: String
}

@available(iOS 18.0, *)
enum AppAttest {

    /// Where the enclave key's identifier is remembered between launches.
    ///
    /// The identifier is a handle, not a secret — the key itself lives in the
    /// Secure Enclave and cannot be exported — so `UserDefaults` is sufficient and,
    /// unlike the Keychain, is readable during a background refresh without an
    /// access-group dance. Losing it is not fatal: the next heartbeat generates a
    /// new key and attests it.
    private static let keyIDDefaultsKey = "com.callerapi.lcid.attestKeyID"

    /// Whether the key behind `keyIDDefaultsKey` has been attested to the server.
    ///
    /// Tracked separately because generating a key and having its attestation
    /// accepted are different events: an attestation can be produced and then lost
    /// to a network failure, and sending an assertion for a key the server has
    /// never seen would fail every time with nothing to explain why.
    private static let attestedDefaultsKey = "com.callerapi.lcid.attestKeyAttested"

    /// Whether App Attest can run at all on this device.
    ///
    /// False on the simulator and on devices without the hardware. Checked before
    /// anything else so no challenge is requested that could never be answered.
    static var isSupported: Bool {
        #if canImport(DeviceCheck)
        return DCAppAttestService.shared.isSupported
        #else
        return false
        #endif
    }

    /// Produces material for one heartbeat, or nil when this device cannot attest.
    ///
    /// `challenge` must come from `/api/lcid/attest/challenge`: the server issues it
    /// single-use, which is what stops captured material being replayed.
    static func material(challenge: String) async -> AttestationMaterial? {
        #if canImport(DeviceCheck)
        guard isSupported, !challenge.isEmpty else { return nil }
        let service = DCAppAttestService.shared

        let defaults = UserDefaults.standard
        do {
            let keyID: String
            if let existing = defaults.string(forKey: keyIDDefaultsKey) {
                keyID = existing
            } else {
                keyID = try await service.generateKey()
                defaults.set(keyID, forKey: keyIDDefaultsKey)
                // A brand-new key has to be attested before it can be asserted with,
                // even if a previous key on this device already was.
                defaults.set(false, forKey: attestedDefaultsKey)
            }

            let hash = clientDataHash(challenge)

            // A key the server has not yet accepted must be attested, not asserted.
            if !defaults.bool(forKey: attestedDefaultsKey) {
                let attestation = try await service.attestKey(keyID, clientDataHash: hash)
                return AttestationMaterial(
                    challenge: challenge,
                    attestation: attestation.base64EncodedString(),
                    assertion: nil,
                    keyID: base64KeyID(keyID)
                )
            }

            let assertion = try await service.generateAssertion(keyID, clientDataHash: hash)
            return AttestationMaterial(
                challenge: challenge,
                attestation: nil,
                assertion: assertion.base64EncodedString(),
                keyID: base64KeyID(keyID)
            )
        } catch {
            // The common recoverable failure is a key iOS has invalidated — after a
            // restore to a new device, for instance. Forgetting it lets the next
            // heartbeat start over with a fresh key rather than failing forever.
            if isInvalidKey(error) {
                forgetKey()
            }
            print("[CallerAPI][LCID] attestation unavailable: \(error.localizedDescription)")
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Records that the server accepted an attestation, so later heartbeats send
    /// the much cheaper assertion instead.
    static func markAttested() {
        UserDefaults.standard.set(true, forKey: attestedDefaultsKey)
    }

    /// Discards the remembered key so the next heartbeat generates and attests a
    /// new one.
    ///
    /// Called when the server reports it has no key on record for us — which
    /// happens legitimately after an operator revokes a client's attestation state
    /// — and when iOS invalidates the key underneath us.
    static func forgetKey() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: keyIDDefaultsKey)
        defaults.set(false, forKey: attestedDefaultsKey)
    }

    /// The server computes `SHA256(challenge)` and folds it into the nonce it
    /// expects Apple to have certified, so this has to hash exactly the challenge
    /// bytes and nothing else.
    private static func clientDataHash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(challenge.utf8)))
    }

    /// Apple's key identifier is already base64 of the SHA-256 of the public key,
    /// so it travels as-is; the server accepts either base64 alphabet.
    private static func base64KeyID(_ keyID: String) -> String { keyID }

    private static func isInvalidKey(_ error: Error) -> Bool {
        #if canImport(DeviceCheck)
        return (error as? DCError)?.code == .invalidKey
        #else
        return false
        #endif
    }
}
#endif
