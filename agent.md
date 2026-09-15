# agent.md — eID (MOSIP Claim 169 QR + Face + Fingerprint)

> Read this first when working in this repo. Server: Node.js + Express. ML: Python (InsightFace + NBIS).

## 1. What this project is

Offline-verifiable eID credential:
`enroll (face + fingerprint + dob) → MOSIP Claim 169 CWT → COSE_Sign1 (EdDSA) → zlib → COSE_Encrypt0 (direct/A256GCM) → Base45 → alphanumeric QR (EC-L)`.
Verify flow mirrors **MOSIP app verification**: `scan QR → authenticate → demographics → live face match → fingerprint match (mobile-side)`.

No portrait in QR — only irreversible face hash/template + ISO 19794-2 FMR.

## 2. Layout

```
server.js                  Express app, static public/, /api/*, central error handler
routes/enroll.js           POST /api/enroll, GET /api/issuer, GET /api/record/:id, POST /api/verify, POST /api/verify-face
routes/facebdb.js          POST /api/face-bdb (photo -> 39794-5 .bin)
routes/faceformats.js      POST /api/face-hash (65B), POST /api/face-template (132B)
routes/fingerprint.js      POST /api/fingerprint (image -> FMR .bin)
lib/mosip.js               QR spec: Claim169 + COSE + Base45 + issue/decode. SOURCE OF TRUTH for QR format
lib/qr.js                  QR render: alphanumeric EC-L, budget 4296, extractAlphaSegmentPayload
lib/crypto.js              CEK provider (ENCRYPTION_KEY 64hex)
lib/keys.js                Issuer (QR_ISSUER https, QR_TTL_DAYS, ED25519 seed, kid = sha256(SPKI)[0:8])
lib/images.js              validateFaceBdb (0x65 DER), extractJp2FromBdb, validate/compactFmr (top-32/view)
lib/store.js               data/records.json {v,id,ts,meta,sizes,hashes,iss,exp} — no biometrics
scripts/facematch.py       InsightFace buffalo_l matcher + hash/template codecs
scripts/face39794_5.py     Photo -> 39794-5 BDB
scripts/fingerprint19794_2.py  NBIS mindtct -> ISO 19794-2 FMR
public/verify.html         Reference verify UX (scan/upload/paste + live face). Mirror in mobile
public/index.html          Reference enroll UX
docs/enroll.mmd, verify.mmd Flowcharts (regenerate SVG via `npm run diagrams`)
tools/nbis/bin/mindtct     Fingerprint extractor binary
tests/mosip.test.js, qr.test.js          Node tests (`npm test`)
tests/test_*.py                            Python tests
```

## 3. Run / dev / test

```bash
cp .env.example .env   # then fill ENCRYPTION_KEY + ED25519_SIGNING_KEY (64hex each):
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
npm install
npm start               # or npm run dev (nodemon). PORT default 3002
npm test                # node tests/mosip.test.js && node tests/qr.test.js
pip install -r scripts/requirements-ml.txt   # InsightFace buffalo_l, CPU; models under data/models
```

Key env (` .env.example`): `PORT | ENCRYPTION_KEY | QR_ISSUER (https://...) | QR_TTL_DAYS=730 | QR_ID_FREE=false | ED25519_SIGNING_KEY | FACE_MATCH_THRESHOLD=0.55 | FACE_TEMPLATE_MATCH_THRESHOLD=0.30 | FACEMATCH_PYTHON=.venv-ml/bin/python | FACE_MATCHER=insightface|baseline | MINDTCT_BIN`.

Current dev `.env` has `QR_ID_FREE=true` — code MUST support both variants (try `decodeQr` then `decodeIdFreeQr`).

## 4. QR spec (do not reinvent — port `lib/mosip.js`)

- Physical: alphanumeric only, EC-L, budget `4296` chars, charset `0-9A-Z $%*+-./:`. `generateQrAlpha()` uppercases. Decode: ZXing `TRY_HARDER`, rotations `[0,90,180,270]` × widths `[orig,800,700,600,500,400,330]`, count-bits try `[13,11,9]`, then Base45 check.
- Logical encrypted (`issueQr`): `claims{1:iss,4:exp,5:nbf,6:iat,169:identity} → CBOR → COSE_Sign1(EdDSA/-8,kid) → zlib.deflate → COSE_Encrypt0(direct/-6+A256GCM/3,CEK,iv12) → Tag(61) → Base45`.
- Logical ID-free (`issueIdFreeQr`): same claims (identity WITHOUT key `1:id`) `→ Sign1 → zlib → Base45` (no encrypt).
- Identity Map (169): `{1:id? , 4:name?, 8:dob YYYYMMDD!, 62:faceHash bstr, 51:[{0:fmr,1:1,2:1}]}`.
- Portrait extension (mobile reads, issuer opts in): portrait JPEG as bstr, or base64 text as tstr, under identity key `63` (preferred) or any other identity key — the reader hunts all of them (case-safe: uppercasing applies only to the outer Base45 layer, never inner CBOR). BDB-wrapped portraits are TLV-walked to the inner JP2. Renderable on-device: JPEG/PNG only — JP2/BDB is detected and reported, never rendered, so issuers must embed JPEG/PNG. Embed ONLY in encrypted QRs (id-free would leave the photo signed-but-plaintext). Absence/non-image → null, verification unaffected.
- Face: `65B 0x01...` (`arcface-sign-512`, match `1-hamming`, thresh `0.55`) OR `132B 02 01 80 7f...` (`arcface-projected-int8`, cosine, thresh `0.30`). Anything starting `0x65` or map-wrapped → reject `unsupported-legacy-qr`.
- Finger: ISO 19794-2:2005 `FMR` magic, compacted top-32 minutiae/view, `<300B` (~222B typ).
- Base45: DGC variant; always `qrText.toUpperCase()` before decode.
- `kid = sha256(SPKI DER).hex[0:16]`. Verify `prot.alg`, `kid`, `exp/nbf`.

## 5. API contracts

- `GET /health → {ok:true}`
- `GET /api/issuer → {iss,kid,alg:EdDSA,publicKeyJwk}` — mobile pins this for offline verify.
- `POST /api/enroll` multipart `faceBdb* + fingerprintTemplate* + dob* (YYYYMMDD) + name? + idNumber?` → `{id,v:9,qrMode,ecLevel,qrDataUrl,qrImageUrl,qrText,sizes,iss,exp,thumb,warning?}`. `413` if `qrText>4296` (record saved `qrFitted:false`). Self-checks decode before persist.
- `GET /api/record/:id` → record metadata only (no biometrics).
- `POST /api/verify` JSON `{qrText}` OR multipart `qrImage` → `VerifyResult {valid,id,reason,checks{authentic,recordFound,imagesMatch},meta,demographics,iss,exp,faceHash{format,bytes,sha256,hex},fingerprintTemplate{...}}`.
  - `reason`: `null|no-qr-detected|unknown-key|expired|not-yet-valid|unsupported-legacy-qr|auth-failed|malformed-qr|unknown-record|images-mismatch`. ID-free valid → `id:null, recordFound:false`.
  - Rule: `sha256(face+fmr)` vs stored record; never match biometrics if `!valid`.
- `POST /api/verify-face` multipart `photo* + (qrImage|qrText)` OR JSON `{qrText*,photoDataUrl*}` → base result + `faceMatch{score,threshold,match,backend}`. Mismatch → `valid:false,reason:face-mismatch`. No face → `no-face-detected,score:null`. Threshold by face type.
- Limits: `5MB` uploads (`multer.memoryStorage`). Central error handler maps `LIMIT_FILE_SIZE→413`, else `400`.

## 6. Face / fingerprint details

- `facematch.py`: `--hash-of → {hash,backend}`, `--match-hash img hex → {score,backend}`, `--template-of`, `--match-template`. Exit `3` = no-face, `2` = model-unavailable/fail-closed. Projection seed `39794`, dim `128`, quant `127`. Backend `insightface-buffalo_l`; `baseline` (NCC+dHash) is dev-only, never for hash/template modes.
- Node callers in `routes/enroll.js`: `runFaceHash`, `runFaceMatchHash`, `runFaceMatchTemplate` via `execFile(FACEMATCH_PYTHON, scripts/facematch.py, timeout 120s)`, temp dirs cleaned up.
- Fingerprint: `fingerprint19794_2.py` needs `mindtct` (`tools/nbis/bin/mindtct` or `MINDTCT_BIN`). No server-side finger-match endpoint — mobile matches live capture vs QR `fmr` (OTG reader + ISO SDK, e.g. Innovatrics/Neurotech, or add server `bozorth3` endpoint mirroring `verify-face`).
- Size estimate: `qrEstChars(bdb,fmr=222)`: `cbor≈10+37+5+(3+bdb)+(3+fmr)`, `+85 sign`, `+47 enc`, `×1.5 Base45` (`routes/facebdb.js`).

## 7. Conventions for agents

- Smallest diff; derive `oldString` from `Read` output (line-number prefix is not file content). One `in_progress` todo at a time; verify with `npm test` + relevant curl (`/health`, `/api/issuer`, `/api/verify`).
- Never commit secrets (`.env`, `data/records.json`, `public/qrcodes/*`, `*.bin`, `*.dat`). Never embed `ENCRYPTION_KEY`/Ed seed in client code or logs. Truncate `hex/qrText` in logs.
- Error shape: `{error:...}` with `400/413/500`; verify verdicts always `200` with `valid:false+reason` (except missing params → `400`). Preserve `reason` strings exactly — mobile + `verify.html` depend on them.
- Record version const `VERSION=9` in `routes/enroll.js`; bump + migrate `lib/store.js` shape together.
- When touching QR/crypto: update `lib/mosip.js` + `tests/mosip.test.js + qr.test.js` + `docs/*.mmd` together, run `npm run diagrams` if `mmd` changed.
- Python changes: keep stdout pure JSON (redirect model chatter to stderr), preserve exit codes `0/2/3`.

## 8. Mobile import (QR scan + face + finger, MOSIP-style)

Flow: `GET /api/issuer (pin JWK) → scan QR (ML Kit/ZXing/AVFoundation, uppercase) → offline decode (Base45→CBOR→decrypt?→inflate→EdDSA verify→expiry) → show demographics/checks → live face (online POST /api/verify-face first; offline bundle buffalo_l ONNX later) → fingerprint 1:1 vs QR fmr via reader SDK → final VALID = QR authentic (+imagesMatch if online) AND face AND finger`.
Port `lib/mosip.js` per platform (Dart: `cbor+cryptography+archive`; Kotlin: `cose-java+jackson-cbor+Tink`; Swift: `SwiftCBOR+CryptoKit+Curve25519`). Gate biometric screens on `valid==true`. Reuse `reason` enum + `checks{authentic,recordFound,imagesMatch,faceMatch}` labels from `public/verify.html`.
