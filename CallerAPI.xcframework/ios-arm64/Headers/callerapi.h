#ifndef CALLERAPI_H
#define CALLERAPI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef _WIN32
#  define CALLERAPI_EXPORT __declspec(dllexport)
#else
#  define CALLERAPI_EXPORT __attribute__((visibility("default")))
#endif

/* Error codes */
#define CALLERAPI_OK            0
#define CALLERAPI_ERR_INIT     -1
#define CALLERAPI_ERR_AUTH     -2
#define CALLERAPI_ERR_HTTP     -3
#define CALLERAPI_ERR_CRYPTO   -4
#define CALLERAPI_ERR_PARSE    -5
#define CALLERAPI_ERR_IO       -6
#define CALLERAPI_ERR_EXPIRED  -7
#define CALLERAPI_ERR_NOTFOUND -8
/* Another thread holds the SDK lock. Only ever returned by the non-blocking
   call-path entry points, which refuse to wait rather than delay a ringing
   phone. Treat exactly like CALLERAPI_ERR_NOTFOUND: the answer is unknown. */
#define CALLERAPI_ERR_BUSY     -9

/*
 * Runtime configuration (see callerapi_init_ex).
 *
 * Any field left NULL/0 falls back to the value compiled into the binary. That
 * fallback is what a per-customer build bakes in; supplying credentials here
 * instead is what allows ONE published artifact to serve every customer, so it
 * can ship through Maven Central / SwiftPM / npm like any other dependency.
 */
typedef struct {
    const char *cache_dir;          /* required: writable, must already exist  */
    const char *api_base;           /* e.g. "https://api.callerapi.com"        */
    const char *sdk_key;            /* per-customer SDK key                    */
    const char *sdk_secret;         /* per-customer HMAC signing secret        */
    int         lookup_timeout_ms;  /* call-path budget (default 2500)         */
    int         network_timeout_ms; /* bulk/background budget (default 30000)  */

    /*
     * App identity, reported on every authentication so the server can refuse a
     * credential presented by an app it was not issued to. The platform wrappers
     * fill these in from the OS — Android from PackageManager, iOS from the main
     * bundle — so host apps do not set them by hand.
     *
     * These are NOT secrets and are not treated as any: the package name is
     * public and the certificate digest is derivable from the published APK. They
     * are a binding, checked against what the operator provisioned for the
     * client, so a credential lifted out of one app stops working in another.
     *
     *   package_name - Android applicationId, or the iOS bundle identifier.
     *   cert_sha256  - Android signing certificate SHA-256, hex (colons and case
     *                  do not matter). Leave NULL on iOS, which has no analogue.
     */
    const char *package_name;
    const char *cert_sha256;

    /*
     * Host app version, reported so the server's version policy can tell an
     * outdated integration from a current one. Defaults to the SDK's own version.
     */
    const char *app_version;
} callerapi_config;

/*
 * Initialize the SDK with runtime configuration. Must be called once before any
 * other function. Returns CALLERAPI_OK on success.
 */
CALLERAPI_EXPORT int callerapi_init_ex(const callerapi_config *cfg);

/*
 * Initialize using only the compiled-in credentials.
 * Equivalent to callerapi_init_ex(&(callerapi_config){ .cache_dir = cache_dir }).
 */
CALLERAPI_EXPORT int callerapi_init(const char *cache_dir);

/*
 * Privacy-preserving spam check (k-anonymity hash-prefix lookup).
 *
 * The device hashes the number, reveals only the resulting bucket index to the
 * server (one of many candidates), fetches that whole bucket, and matches the
 * full-hash suffix locally - the server never learns which number was queried.
 * Buckets are cached in memory, so repeat checks are local and instant.
 *
 * phone must be E.164 format (e.g. "+16612351234").
 * Returns 1 (spam), 0 (not spam), or a negative error code.
 * Transparently authenticates if no valid session exists.
 */
CALLERAPI_EXPORT int callerapi_is_spam(const char *phone);

/*
 * Non-blocking spam check for the incoming-call path.
 *
 * NEVER performs network I/O and never waits on the SDK lock, so it is safe to
 * call from a CallScreeningService callback where any delay holds up a ringing
 * phone. Answers only from the in-memory bucket cache.
 *
 * Returns 1 (spam), 0 (definitively not in the cached bucket),
 * CALLERAPI_ERR_NOTFOUND (bucket not cached — answer unknown) or
 * CALLERAPI_ERR_BUSY. Treat anything negative as "unknown", let the call
 * through, and call callerapi_prewarm() off the call path so the next call from
 * that bucket can be answered.
 */
CALLERAPI_EXPORT int callerapi_is_spam_cached(const char *phone);

/*
 * Warm the session and namespace config, and populate the bucket cache for
 * `phone` when it is non-NULL. Performs network I/O, so call it off the
 * call path (init, background refresh, or right after a cache miss).
 * Returns CALLERAPI_OK or a negative error code.
 */
CALLERAPI_EXPORT int callerapi_prewarm(const char *phone);

/*
 * Privacy-preserving business-label lookup (same k-anonymity mechanism as
 * callerapi_is_spam, over the identity namespace). On a hit, writes the
 * caller's business name into `out` (NUL-terminated, truncated to out_len).
 *
 * phone must be E.164 format.
 * Returns CALLERAPI_OK on a match, CALLERAPI_ERR_NOTFOUND if the number is not a
 * known business, or another negative error code.
 */
CALLERAPI_EXPORT int callerapi_lookup_label(const char *phone,
                                            char       *out,
                                            int         out_len);

/*
 * Perform an authenticated GET on `path` (relative to the configured API base)
 * and return the response body.
 *
 * Exists so features that are pure JSON reads — the Business Caller ID assertion
 * feed and logo pack — can live in the platform wrapper without reimplementing
 * authentication. Session establishment is HMAC over an obfuscated credential
 * pair; a second implementation of that in Kotlin and Swift would be two more
 * places for it to drift, and drift in an auth protocol is a silent outage.
 *
 * Note that the path is supplied by the caller rather than obfuscated in here
 * like the core endpoints. Endpoint paths are visible in traffic to anyone who
 * can see it, so hiding them buys little; the obfuscation exists to slow down
 * extraction of the credential pair, which this does not touch.
 *
 * On CALLERAPI_OK, *body_out is a NUL-terminated buffer the caller must free.
 * Returns CALLERAPI_ERR_HTTP for any non-200, so a caller cannot mistake an
 * error page for data.
 */
CALLERAPI_EXPORT int callerapi_authed_get(const char *path,
                                         int         timeout_ms,
                                         char      **body_out);

/*
 * Configure metering fields sent on the next authentication (control-plane
 * check-in for MAU / billing). All arguments are optional:
 *   device_id        - stable per-vendor id (Android App Set ID / iOS IDFV).
 *                       If non-NULL
 *                       and non-empty, overrides the locally generated UUID so
 *                       the server counts one active device per vendor install.
 *   feature_enabled  - 1 if the call-blocking feature is toggled on, else 0.
 *   blocks_reported  - consented cumulative blocked-call counter (0 if none).
 * Call before the first lookup so the values ride the initial auth.
 */
CALLERAPI_EXPORT void callerapi_set_metering(const char *device_id,
                                             int         feature_enabled,
                                             long long   blocks_reported);

/*
 * Force a control-plane check-in: re-authenticates immediately so the metering
 * fields set via callerapi_set_metering are posted to the server now (used by
 * the periodic background heartbeat for MAU). Returns CALLERAPI_OK or an error.
 */
CALLERAPI_EXPORT int callerapi_checkin(void);

/*
 * ── Call Directory protected blocklist (legacy iOS 13-17) ───────────────────
 *
 * iOS does not allow a per-call network lookup before iOS 18, so older devices
 * block spam via a CXCallDirectory extension that matches incoming calls against
 * a pre-loaded LOCAL list. These two functions fetch that list privately and
 * keep it encrypted on disk so it cannot be scraped from traffic or the device.
 *
 * Typical flow:
 *   - Host app (periodically / on demand):  callerapi_calldir_sync(...)
 *   - Call Directory extension (on reload):  callerapi_calldir_load(...)
 *
 * `at_rest_key` is a stable 32-byte device key the host stores in the iOS
 * Keychain (kSecAttrAccessibleAfterFirstUnlock, shared with the extension via
 * an access group). The same key MUST be passed to sync and load.
 */

/*
 * Fetch + decrypt + re-encrypt-at-rest the full current Call Directory blocklist
 * (always the rolling window; no incremental/since). Network + auth happen here,
 * so call from the host app, not the extension.
 *   out_path - app-group file path the encrypted-at-rest blob is written to.
 * Returns CALLERAPI_OK or a negative CALLERAPI_ERR_*.
 */
CALLERAPI_EXPORT int callerapi_calldir_sync(const uint8_t at_rest_key[32],
                                            const char   *out_path);

/*
 * Callback invoked once per blocklist number (E.164 with the leading '+'
 * removed, i.e. the CXCallDirectoryPhoneNumber form). Numbers arrive in
 * ascending order, as CallKit requires.
 */
typedef void (*callerapi_calldir_cb)(int64_t number, void *user);

/*
 * Decrypt the at-rest blob written by callerapi_calldir_sync and emit every
 * number via cb. Offline (no network, no session), safe to run inside the
 * memory-constrained Call Directory extension.
 *   blob_path - same path passed as out_path to callerapi_calldir_sync.
 * Returns CALLERAPI_OK or a negative CALLERAPI_ERR_*.
 */
CALLERAPI_EXPORT int callerapi_calldir_load(const uint8_t at_rest_key[32],
                                            const char   *blob_path,
                                            callerapi_calldir_cb cb,
                                            void *user);

/*
 * Tear down: free all memory, close network handles.
 */
CALLERAPI_EXPORT void callerapi_cleanup(void);

#ifdef __cplusplus
}
#endif
#endif /* CALLERAPI_H */
