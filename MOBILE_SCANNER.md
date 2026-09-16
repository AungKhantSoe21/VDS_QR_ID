# Mobile QR ID Scanner — eID Integration Guide

Scan the MOSIP Claim 169 QR on-device and verify identity offline using pinned Ed25519 public key.

> Server source of truth: `routes/enroll.js`, `lib/mosip.js`, `lib/keys.js`

---

## 1. How the QR payload works (v14+ signed-only)

```
demographics (id, name, dob) + face template (68B/132B) + fingerprints (2× FMR)
  → CWT Claims Map {4: exp, 169: identity}
  → CBOR encode
  → COSE_Sign1 (EdDSA / Ed25519, 64B signature)
  → zlib deflate (level 9)
  → Base45 encode
  → Alphanumeric QR (EC-L)
```

What the phone must do:

```
camera frame → read text (Base45 alphanumeric string)
  → Base45 decode → compressed bytes
  → zlib inflate → COSE_Sign1 CBOR
  → verify Ed25519 signature against pinned public key
  → parse CWT claims → identity map
  → extract face template + fingerprints for verification
```

### 1.1 Key

No encryption key needed. The app verifies signatures using a pinned Ed25519 public key in `lib/config/issuer.dart`. This is PUBLIC key material (safe to commit).

For production, replace the dev issuer values with the real issuer's `iss`/`kid`/JWK `x` from `GET /api/issuer` on the backend.

### 1.2 Verification

Fully offline — no network required after install. The app:

1. Base45 decodes the QR text
2. Inflates (zlib decompresses) the result
3. Verifies the COSE_Sign1 Ed25519 signature against the pinned public key
4. Checks expiry (`exp` claim)
5. Parses the identity map (Claim 169)

---

## 2. QR text format

The QR contains an **alphanumeric** Base45 string (not binary bytes, not base64).

- Character set: `0-9 A-Z space $ % * + - . / :`
- Max length: 4296 chars (V40-L capacity)
- Typical length: 700–1800 chars

Detection: match `^[0-9A-Z $%*+\-./:]+$`, length 100–4296.

---

## 3. CWT Claims Map

```cbor
{
  4: exp,           // expiry (Unix epoch seconds)
  169: identity     // MOSIP Claim 169 identity map
}
```

### 3.1 Claim 169 Identity Map

| CBOR Key | Name | Value |
|----------|------|-------|
| 1 | `id` | 10-digit national ID string |
| 4 | `name` | Full name |
| 8 | `dob` | Date of birth (YYYYMMDD) |
| 50 | Right thumb | `[{0: FMR bytes, 1: 1, 2: 1}]` |
| 55 | Left thumb | `[{0: FMR bytes, 1: 1, 2: 1}]` |
| 62 | Face biometrics | `[{0: template bytes, 1: 1, 2: 100\|101}]` |

### 3.2 Biometric Entry

| CBOR Key | Name | Value |
|----------|------|-------|
| 0 | Data | Raw template bytes |
| 1 | Format | `1` = template |
| 2 | Subformat | `1` = ISO 19794-2 (finger), `100` = face v2 (132B), `101` = face v3 (68B) |

### 3.3 COSE_Sign1 Headers

| Tag | Header | CBOR Key | Value |
|-----|--------|----------|-------|
| 18 | Protected | 1 | `-8` (EdDSA) |
| 18 | Unprotected | 4 | `kid` = sha256(DER ds.crt)[0:8] as bytes |

---

## 4. Verification flow

```
Base45 decode → raw bytes
  → zlib inflate → COSE_Sign1 CBOR (Tag 18)
  → verify Ed25519 signature
  → parse CWT claims
  → check exp
  → parse identity (Claim 169)
  → extract face template + fingerprints
```

The app (`lib/services/mosip.dart`) handles this fully offline:

```dart
final credential = await verifyQrTextOffline(qrText);
// credential.id, credential.name, credential.dob
// credential.faceHash, credential.fingerprints
```

---

## 5. Face verification

After QR verification, the app performs on-device face matching:

1. Capture live selfie via camera
2. Run face model (ArcFace) on-device to extract face embedding
3. Compare against the face template from the QR (claim key 62)
4. Match if similarity score >= threshold

This requires face models (~1.5 MB) which are bundled in the APK and copied to device storage on first use.

---

## 6. Troubleshooting

- **`malformed-qr`** → Not a valid Base45 QR, or corrupt/compressed data
- **`auth-failed`** → Signature verification failed — tampered QR
- **`unknown-key`** → Signed by an unknown issuer — issuer key rotated? Re-pin
- **`expired`** → QR expired — re-enroll this person
- **`not-yet-valid`** → QR not yet valid — check device clock
- **No detection** → Dense QR needs good focus/light; hold 15–30 cm

---

## 7. Minimal scanner UX checklist

- [ ] Continuous scan, stop on first decodable frame
- [ ] Show `VALID/INVALID + reason` (authentic, expired, unknown-key, etc.)
- [ ] Show `id`, `name`, `dob`, face match result
- [ ] Handle `malformed-qr` by continuing, not erroring
- [ ] Offer face capture step after QR verified
- [ ] Never log the private key or full plaintext blobs
