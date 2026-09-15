# eID Image Encryption → Decryption → Display

Short answer: **No, images are NOT encrypted as base64.** Encryption works on raw binary bytes. Base64 appears only at two transport edges: (1) server JSON record fields, (2) `data:` URLs for browsers. If your mobile scan returns `id/name/ts` but images won't render, you almost certainly corrupted the binary at one of those edges (treated bytes as String, wrong MIME, or no AVIF decoder).

Server truth: `lib/images.js`, `lib/codec.js`, `lib/crypto.js`, `routes/enroll.js:27-30,174-178,276-279`.

---

## 1. Enroll: how the image is encrypted

### Step 1 — sharp produces RAW bytes (not base64, not dataURL)

```js
// lib/images.js processThumbRaw() — what goes into the QR
passport    -> rotate -> resize 128x160 -> avif({quality:35}) -> Buffer <~1-2KB>
fingerprint -> rotate -> grayscale -> resize 128x128 -> avif({quality:32}) -> Buffer

// processFullRaw() — server-only record, never in QR
passport    -> resize width:320 -> jpeg({quality:65}) -> Buffer
fingerprint -> grayscale -> resize width:300 -> jpeg({quality:60}) -> Buffer
```

At this point `pt.buffer` / `ft.buffer` are raw `Buffer` objects. First bytes tell you the format:

- JPEG: `FF D8 FF ...`
- AVIF: `00 00 00 1C 66 74 79 70 61 76 69 66` (`....ftypavif`)

### Step 2 — CBOR packs raw bytes (still binary, no base64)

```js
// lib/codec.js
encodeEnroll({id, ts, name, idNumber, fmt, passport, fingerprint}) =
  CBOR([3, id, ts, name, idNumber, fmt, passportBuf, fingerprintBuf])
// passportBuf / fingerprintBuf = CBOR byte-strings (major type 2), raw image bytes preserved 1:1
```

CBOR array schema v3: `[v, id, ts, name, idNumber, fmt, passport, fingerprint]`. No keys, no base64, no JSON. `qrCbor.length` is logged in `sizes.qrCborBytes`.

### Step 3 — AES-256-GCM encrypts BYTES (still binary)

```js
// lib/crypto.js encryptBuffer(plaintextBuf)
iv = randomBytes(12)
cipher = createCipheriv('aes-256-gcm', hex(ENCRYPTION_KEY), iv)
ciphertext = cipher.update(qrCbor) + cipher.final()
authTag = cipher.getAuthTag() // 16 bytes
return {iv: base64, authTag: base64, ciphertext: base64}
```

> The `base64` here is only because the record is stored as JSON in `data/records.json`. The cipher itself consumed and produced bytes. Never base64 the image before this step — that would bloat it ~33% and break the 2800-byte QR budget.

### Step 4 — Envelope CBOR → QR raw bytes

```js
// lib/codec.js packQrEnvelopeBytes({iv, authTag, ciphertext})
envelopeBytes = CBOR([3, ivBytes, tagBytes, ctBytes]) // base64 decoded back to bytes first!
// generateQrBinary(envelopeBytes) -> QR byte-mode segment, EC-L
```

`envelopeBytes` is what lives in the QR image. `qrEnvelopeB64url = envelopeBytes.toString('base64url')` exists only for JSON transport to `/api/scan` and debugging.

Full chain:

```
sharp Buffer -> CBOR byte-string -> AES-GCM ciphertext bytes -> CBOR envelope bytes -> QR modules
```

---

## 2. Verify: how the image comes back as the original

Reverse, bytes stay bytes until the very last render line:

```js
// routes/enroll.js verifyEnvelopeBytes()
envelope      = unpackQrEnvelopeBytes(envelopeBytes) // CBOR -> {iv, authTag, ciphertext} (base64 strings)
plain         = decryptToBuffer(envelope)            // AES-GCM -> qrCbor Buffer (exact bytes from Step 2)
decoded       = decodeEnroll(plain)                  // CBOR -> {v,id,ts,meta,fmt,images:{passport:Buffer,fingerprint:Buffer}}
// images.passport / .fingerprint are byte-identical to sharp output in Step 1
// (server proves it: sha256(decoded.images.passport) === record.hashes.thumbPassport)

// ONLY here does base64 appear — for the browser <img> tag:
function toDataUrl(buf, fmt) {
  const mime = fmt === 'avif' ? 'image/avif' : 'image/jpeg';
  return `data:${mime};base64,${buf.toString('base64')}`;
}
```

`/api/verify` and `/api/scan` return:

```json
{"images": {"passportImage": "data:image/avif;base64,AAAA...", "fingerprintImage": "data:image/avif;base64,BBBB..."}}
```

`verify.html` just does `thumbP.src = v.images.passportImage`. That is the "original" (the 128px AVIF thumb; full 320px JPEG never leaves the server except via `/api/decrypt/:id` dev endpoint).

---

## 3. Why mobile gets text fields but no image

If `id/name/ts` decode but `<Image>` is blank, one of these happened:

| # | Bug | Symptom |
|---|---|---|
| 1 | `String(passportBytes)` / `bytes.toString()` / `rawValue` | CBOR byte-string decoded as UTF-8 text → random AVIF bytes become `�`, length changes, image header `ftypavif` destroyed. Text fields survive because they ARE strings. |
| 2 | Wrong MIME | `data:image/jpeg` prefix on AVIF bytes (or vice versa) → decoder rejects. `fmt` field tells you: current enrolls emit `fmt='avif'`. |
| 3 | Double / missing base64 | `base64encode(utf8string(bytes))` instead of `base64encode(bytes)`; or feeding raw bytes to a widget expecting base64 string. |
| 4 | No AVIF decoder | Android <12, iOS <16, default Flutter `Image.memory`, RN `<Image>` cannot decode AVIF → blank with no error. |
| 5 | Truncated buffer | Using `displayValue` (max ~2KB, may clip) instead of `rawBytes` → CBOR still parses for small text but image byte-strings are cut. |

Rule: **image byte-strings must travel `Uint8List / ByteArray / Data` end-to-end, never through `String`, until the final base64-for-display line.**

Correct mobile tail:

```
CBOR inner[6], inner[7] as BYTES -> keep as bytes
  -> base64Encode(bytes) ONLY for dataURL / JSON
  -> prefix with mime from fmt
  -> feed bytes (not dataURL) to native image loader where possible
```

---

## 4. Mobile fix — copy-paste patterns

### 4.1 Get bytes out of CBOR correctly

```kotlin
// Android (com.upokecenter:cbor) — GetByteString, NOT AsString/ToString
val passport: ByteArray = inner[6].GetByteString()
val fingerprint: ByteArray = inner[7].GetByteString()
// sanity: passport[4..11] should be "ftyp" for AVIF, or passport[0]==0xFF for JPEG
```

```swift
// iOS (SwiftCBOR / CBORSwift) — cast to Data, NOT String
guard let passport = inner[6] as? Data,
      let fingerprint = inner[7] as? Data else { fatalError("treated image bytes as String") }
```

```dart
// Flutter (cbor package) — List<int>, NOT String
final passport = Uint8List.fromList(List<int>.from(inner[6]));
final fingerprint = Uint8List.fromList(List<int>.from(inner[7]));
// WRONG: inner[6] as String, utf8.decode(passport), String.fromCharCodes(passport)
```

### 4.2 Render with correct MIME

```kotlin
// Android — prefer bytes directly, avoid WebView dataURL when possible
val fmt: String = inner[5].AsString() // "avif" | "jpeg"
imageView.setImageBitmap(BitmapFactory.decodeByteArray(passport, 0, passport.size))
// Coil (AVIF needs Android 12+ or coil-avif plugin):
// imageView.load(passport) { decoderFactory(AvifDecoder.Factory()) }
// dataURL only for WebView: "data:${if(fmt=="avif") "image/avif" else "image/jpeg"};base64," + Base64.encodeToString(passport, NO_WRAP)
```

```swift
// iOS 16+ decodes AVIF via ImageIO. Below that add SDWebImageAVIF:
import SDWebImageAVIFCodec
SDImageAVIFCoder.addToCodersManager()
passportImageView.sd_setImage(with: URL(string: dataUrl))
// or direct: passportImageView.image = UIImage(data: passport)
```

```dart
// Flutter — Image.memory takes BYTES, not base64 string:
Image.memory(passport) // correct
// WRONG: Image.memory(utf8.encode(base64Encode(passport)))
// AVIF: needs `avif` / `flutter_avif` plugin on older engines; else request JPEG thumbs
// dataURL only for web views: 'data:$mime;base64,${base64Encode(passport)}'
```

### 4.3 Quick self-test on device (log these)

```
fmt = ?
passport.length = ? (expect ~800-2500B AVIF thumb)
passport[0..11] hex = ? (expect 00..6674797061766966 for AVIF, FFD8FF for JPEG)
base64(passport).length ≈ ceil(passport.length * 4/3)
sha256(passport) == record.hashes.thumbPassport ? (GET /api/record/:id)
```

If header is `EF BF BD` (`�` replacement char) you UTF-8-mangled the bytes in §3-row-1. Go back to byte API.

---

## 5. End-to-end reference (Node, mirrors server)

```js
const {unpackQrEnvelopeBytes} = require('./lib/codec');
const {decodeEnroll} = require('./lib/codec');
const {decryptToBuffer} = require('./lib/crypto');
require('dotenv').config();

// envelopeBytes = raw QR bytes (or Buffer.from(qrText,'base64url'))
const envelope = unpackQrEnvelopeBytes(envelopeBytes);
const plain = decryptToBuffer(envelope);          // Buffer: exact qrCbor from enroll
const d = decodeEnroll(plain);                    // {v,id,ts,meta,fmt,images:{passport,fingerprint}}
console.log(d.id, d.meta, d.fmt, d.images.passport.length, d.images.fingerprint.length);
require('fs').writeFileSync('out-passport.' + (d.fmt==='avif'?'avif':'jpg'), d.images.passport);
// open out-passport.avif — if this file views fine, server side is correct; bug is in mobile bytes handling.
```

---

## 6. Checklist before asking for help

- [ ] Scanner uses `rawBytes` / `BYTE_SEGMENTS`, not `rawValue`/`displayValue`/`stringValue`.
- [ ] CBOR image fields extracted as bytes (`GetByteString` / `Data` / `Uint8List`), never `String`.
- [ ] MIME comes from `fmt` (`avif`→`image/avif`, else `image/jpeg`).
- [ ] Decoder supports AVIF, or test with a JPEG record (legacy v2).
- [ ] `sha256(passport)` matches `GET /api/record/:id → hashes.thumbPassport`.
- [ ] Node reference script above renders the image — isolates mobile vs server fault.