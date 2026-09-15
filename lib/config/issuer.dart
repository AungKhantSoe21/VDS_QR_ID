/// Pinned issuer identity for fully-offline QR verification.
///
/// This is PUBLIC key material (safe to commit): `GET /api/issuer` on the
/// backend returns exactly this. The app verifies the QR's `COSE_Sign1`
/// EdDSA signature against [publicKeyBytes] with no network (agent.md §8:
/// "mobile pins this for offline verify").
///
/// Dev values below match the local backend `mm_ed25519_ds` DS cert.
/// For production, replace with the real issuer's `iss`/`kid`/JWK `x` and
/// re-pin. A rotated issuer key surfaces as `unknown-key` (encrypted QRs)
/// or `auth-failed` (id-free QRs) — never as a false VALID.
class IssuerPin {
  static const iss = 'https://eid.example.org';

  /// kid = sha256(DER ds.crt).hex[0:16].
  static const kid = '5911bf77f88d015c';
  static const alg = 'EdDSA';

  /// Ed25519 public key bytes (32 bytes), from the DS cert JWK `x`.
  static const publicKeyBase64Url = '3i9fr0P2F2bQZO1_XOg-iNLcKAMtYFNrmglWA4UP_tA';

  /// X.509 certificate chain: [DS cert PEM, CSCA trust anchor PEM].
  /// Offline verifiers pin this to check the signer's identity.
  static const x5c = <String>[
    'MIIBozCCAVWgAwIBAgIUALQIbRIM+d0sHec2Dgsz0fcwHmAwBQYDK2VwMEsxCzAJBgNVBAYTAk1NMRAwDgYDVQQKDAdQb0MgR292MSowKAYDVQQDDCFDU0NBIE1NIEltbWlncmF0aW9uIFBvQyAoRWQyNTUxOSkwHhcNMjYwOTE0MDg1MjExWhcNMjcwOTE0MDg1MjExWjBJMQswCQYDVQQGEwJNTTEQMA4GA1UECgwHUG9DIEdvdjEoMCYGA1UEAwwfRFMgTU0gSW1taWdyYXRpb24gUG9DIChFZDI1NTE5KTAqMAUGAytlcAMhAN4vX69D9hdm0GTtf1zoPojS3CgDLWBTa5oJVgOFD/7Qo00wSzAJBgNVHRMEAjAAMB0GA1UdDgQWBBSkD5E66wdJFpt7l2aVGB7U7iRWozAfBgNVHSMEGDAWgBR13YikPmVbjN7otl+exdxkuRTrOTAFBgMrZXADQQBp7jU5MtzKWSvns3FKQeyjHwjVfQrDAbTeJhY6rp5vZF96VYMmt8CC3B9QhMZDxV0rPHeyAovvhbMOr/kPERAI',
    'MIIBqzCCAV2gAwIBAgIUCrZl8InCwBPSjR3JSX0CsTXxDiwwBQYDK2VwMEsxCzAJBgNVBAYTAk1NMRAwDgYDVQQKDAdQb0MgR292MSowKAYDVQQDDCFDU0NBIE1NIEltbWlncmF0aW9uIFBvQyAoRWQyNTUxOSkwHhcNMjYwOTE0MDg1MjExWhcNMzYwOTExMDg1MjExWjBLMQswCQYDVQQGEwJNTTEQMA4GA1UECgwHUG9DIEdvdjEqMCgGA1UEAwwhQ1NDQSBNTSBJbW1pZ3JhdGlvbiBQb0MgKEVkMjU1MTkpMCowBQYDK2VwAyEATtRF59AG8pUNwkXSBPD6cUOgBmIJAoaV+zNAChHQYhujUzBRMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFHXdiKQ+ZVuM3ui2X57F3GS5FOs5MB8GA1UdIwQYMBaAFHXdiKQ+ZVuM3ui2X57F3GS5FOs5MAUGAytlcANBAPNpo8rHPFeHoJWQkXfgB14zU0DKr6lxZAbLyNtegCXNN1VIYALXe66P78TqrBdt043dTYzbm9FdoPrkmY9yqgU=',
  ];
}
