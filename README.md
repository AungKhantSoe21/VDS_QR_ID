# eID Verify (PoC 0.9.0)

Offline identity verification for QR credentials — **no server, no account, no network** after install.

**Flow:** scan QR → offline authenticity check (signature + expiry) → on-device face match → ID card. Fingerprint via an external reader is optional and never a gate.

## What it verifies

| QR format | Contents | Face step |
|---|---|---|
| MOSIP Claim 169 Base45 (encrypted / id-free) | demographics + irreversible face hash + ISO 19794-2 FMR | ArcFace embedding vs hash, on-device |
| Legacy envelope v2/v3 (AES-GCM + CBOR) | demographics + AVIF/JPEG photo + fingerprint photo | human visual confirm (photo, no hash) |

Card faces follow `id_layout_card.md` (Myanmar NRC style, green guilloche theme).

## Getting started

### 1. Backend (test QRs only — the app never talks to it)

The e-id server issues credentials. To mint a test QR:

```bash
cd /home/aks/Documents/eid
node server.js                      # :3002
# enroll via public/index.html, or:
curl -X POST http://localhost:3002/api/enroll \
  -F faceBdb=@hash65.bin -F fingerprintTemplate=@iso2005template \
  -F dob=19900101 -F name="Test User"
# → qrText in the JSON response (paste into the app's debug button,
#    or display public/qrcodes/<id>.png for the camera)
```

Face templates come from `scripts/facematch.py --template-of photo.jpg`
(buffalo_s backend, the enrollment reference; models under `data/models`).

### 2. App

```bash
cd /home/aks/Documents/VDS_QR_ID
flutter pub get
flutter run -d <device>             # camera + biometrics need a real phone
```

First face check copies the bundled face models into place once (~31MB:
SCRFD-500M detector + EdgeFace-S recognizer for current QRs + w600k_mbf
for legacy buffalo QRs, SHA-pinned, offline, takes seconds),
then everything runs offline. Manage it in **Settings** (also: face
threshold, cache clear, about).
then everything runs offline. Manage it in **Settings** (also: face
threshold, cache clear, about).

### 3. Field calibration

`Settings → Face threshold` (default **0.60**, persisted). Raise it if
strangers pass, lower it on false rejects. The live score vs threshold
shows on every check. Keep the server's `FACE_MATCH_THRESHOLD` aligned
for online parity.

## How verification works (all on-device)

1. **QR authenticity** — MOSIP v14+: Base45 → inflate → EdDSA verify
   vs pinned issuer key → expiry
   (`lib/services/mosip.dart`, ported from backend `lib/mosip.js`,
   proven against backend-signed vectors in `test/mosip_test.dart`).
2. **Face** — SCRFD-500M detect → ArcFace align → dual embed
   (EdgeFace-S + legacy w600k_mbf via `onnxruntime`, models
   download-on-first-use) → cosine vs compact template in both spaces,
   better margin-above-threshold wins (current ≥ 0.40, legacy ≥ 0.35),
   or `1-hamming` vs QR hash ≥ threshold
   (`lib/services/face_embedder.dart`, `face_matcher.dart`). Old
   buffalo QRs verify as-is: templates carry no model id, so both
   spaces are tried.
3. **Card** — NRC-styled flip card (`lib/widgets/smart_card.dart`).
   Data only: QRs carry a verification *pattern*, not a photo.
4. **Fingerprint (optional)** — external OTG reader + ISO matcher SDK
   via the `ExternalFingerprintReader` seam. The phone sensor is
   deliberately unused (proves device ownership, not holder identity).

Debug tools (scanner bar): paste-qrText, QR inspector (dumps identity
keys/sizes/magic — answers "where is the image?"), offline self-test.

## VDS positioning

Conceptually close to ICAO VDS (Doc 9303-13): an offline-verifiable,
signed credential checked against pinned trust. **Not VDS-conformant**:
EdDSA + pinned key instead of ECDSA + X.509/CSCA chains, no master
lists or revocation, fixed Claim-169 schema instead of TLV profiles.
Conformance (brainpool ECDSA, chain validation, CSCA distribution,
C40 decode) is a separate track — the staged UX already fits it.

## Layout

```
lib/main.dart                app entry (.env key load), green Material3 theme
lib/config/                  issuer pin, EID key, env parser
lib/models/                  CardData (unified MOSIP/legacy), EidRecord
lib/screens/                 scanner, face, smart card, settings,
                             external reader (optional), QR inspector (debug)
lib/services/                mosip (COSE port), eid_* (legacy),
                             face_embedder/matcher/projection/model_pack,
                             external_finger_reader (seam)
lib/widgets/                 smart_card (NRC UI + painters), verify_steps,
                             identity_image (AVIF/JPEG), progress_dialog
test/                        55+ tests: interop vectors, pipeline math,
                             card layout (360px overflow guard)
agent.md                     backend spec mirror · id_layout_card.md  card spec
image_encryption_backend.md  legacy envelope format reference
```

## Testing

```bash
flutter analyze        # clean
flutter test           # full suite (real backend-signed vectors included)
flutter build apk --debug
```

`backend npm test` covers the issuing side (`/home/aks/Documents/eid`).
