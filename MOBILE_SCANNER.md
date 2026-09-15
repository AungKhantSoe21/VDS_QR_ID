# Mobile QR ID Scanner — eID Integration Guide

Scan the binary eID QR on-device and get decrypted identity data using the server `ENCRYPTION_KEY`.

> Server source of truth: `routes/enroll.js`, `lib/codec.js`, `lib/crypto.js`, `lib/qr.js`

---

## 1. How the QR payload works

```
passport (320px JPEG) + fingerprint (300px JPEG)
  → CBOR full  → AES-256-GCM → stored in data/records.json (fullEncrypted)

passport thumb (128×160 AVIF q35 grayscale)
fingerprint thumb (128×128 AVIF q32 grayscale)
  → CBOR([3, id, ts, name, idNumber, fmt, passportBytes, fingerprintBytes])
  → AES-256-GCM {iv (12B), authTag (16B), ciphertext}
  → CBOR([3, ivBytes, tagBytes, ctBytes]) = envelopeBytes (~<2800B)
  → QR byte-mode segment, EC-L, scale 6 (raw bytes, NOT text)
```

What the phone must do:

```
camera frame → read RAW BYTES (not string) → envelopeBytes
  → CBOR decode → {iv, tag, ct}
  → AES-256-GCM decrypt (key = server ENCRYPTION_KEY)
  → CBOR decode → {id, ts, name, idNumber, fmt, passport, fingerprint}
  → render images
```

### 1.1 Key

Server `.env` (`/home/aks/Documents/eid/env`):

```env
PORT=3002
ENCRYPTION_KEY=9f4d1d882c86f5554ebee4b47c413d4c7b3a430e4cb9bb4b2349101187a75bd1
```

- Format: 64 hex chars = 32 bytes, AES-256.
- Mobile: `keyBytes = hexDecode(ENCRYPTION_KEY)`.
- Do NOT hardcode in git. Inject via `--dart-define`, `local.properties`, Xcode `xcconfig`, or fetch from secure backend at login.

> ⚠️ Security: anyone with this key can decrypt every QR offline. For production prefer **Option B (server verify)** below and keep the key server-only.

### 1.2 Two integration options

|  | A. Offline decrypt (what you asked for) | B. Online verify (recommended) |
|---|---|---|
| Key location | embedded in app | server only |
| Network | none after install | required |
| Endpoint | none | `POST /api/scan` or `POST /api/verify` |
| Trust | client asserts identity | server checks `authentic + recordFound + imagesMatch + metaMatch` |
| Use when | gate / field check, no signal | normal operation |

You can ship both: try B first, fall back to A offline.

---

## 2. Critical: read RAW bytes, not text

The QR holds **random binary bytes**. `stringValue / displayValue / rawValue` will corrupt it (stock camera apps misread it — same note as `POST /api/enroll` response).

Use:

- Android ML Kit: `barcode.rawBytes` (type `ByteArray?`), **never** `rawValue` / `displayValue`.
- Android ZXing: `result.resultMetadata[ResultMetadataType.BYTE_SEGMENTS] as List<ByteArray>` → `[0]`. Fallback: `extractByteSegmentPayload(result.rawBytes)` (port in §5).
- Flutter `mobile_scanner`: `barcode.rawBytes` (`Uint8List?`).
- iOS AVFoundation `stringValue` is **broken** for this QR. Use `zxing-cpp` (`ZXingCpp.readBarcodes`) or `ZXingObjC`. Both return raw bytes / byteSegments.
- React Native VisionCamera code scanner: use the byte-payload field, not `value`.

If your scanner SDK only gives a String, base64url-encode **its ISO-8859-1 bytes** and send to `POST /api/scan` — do not try to decrypt the String directly.

Transport encoding (for API only, not in QR image):

```
qrText = base64url(envelopeBytes)  // no padding, -_ alphabet
       = same as qrEnvelopeB64url in enroll response
```

---

## 3. Binary formats (must match exactly)

### 3.1 QR envelope (outer CBOR)

```js
// lib/codec.js packQrEnvelopeBytes
CBOR([VERSION, ivBytes, tagBytes, ctBytes])
// VERSION = 3 (accept 2 for legacy), each *Bytes is CBOR byte-string
```

Decode with any CBOR lib (`cbor-x` semantics = standard RFC 7049):

```pseudo
[v, iv, tag, ct] = CBOR.decode(envelopeBytes)
assert v == 3 or v == 2
// iv.length == 12, tag.length == 16
```

### 3.2 Inner payload (after AES-GCM decrypt)

```js
// lib/codec.js encodeEnroll v3
CBOR([3, id, ts, name, idNumber, fmt, passportBuf, fingerprintBuf])
// legacy v2: CBOR([2, id, ts, name, idNumber, passportBuf, fingerprintBuf]), fmt='jpeg'
```

```pseudo
arr = CBOR.decode(plaintext)
if arr[0] == 3: [v,id,ts,name,idNumber,fmt,passport,fingerprint] = arr
else if arr[0] == 2: [v,id,ts,name,idNumber,passport,fingerprint] = arr; fmt='jpeg'
```

- `id`: UUID string, `ts`: ISO string, `fmt`: `'avif'` (current) or `'jpeg'`.
- `passport` / `fingerprint`: raw image bytes. Render as `data:<mime>;base64,...` where mime = `image/avif` if fmt==avif else `image/jpeg` (same as `toDataUrl()` in `routes/enroll.js`).

### 3.3 Crypto

```
AES-256-GCM, IV 12B, tag 16B, NoPadding
key = hex(ENCRYPTION_KEY)
plaintext = AES_GCM_DECRYPT(key, iv, ciphertext, tag)
```

Node reference (`lib/crypto.js`): `cipher.getAuthTag()` / `decipher.setAuthTag(tag)`.

---

## 4. Option B — Online (5 minutes, no key in app)

Best for most apps. Let the server decrypt + verify.

```bash
# 1. enroll (web) gives you qrEnvelopeB64url
# 2a. scan path — decode only (no cross-check):
curl -X POST http://SERVER:3002/api/scan \
  -H 'Content-Type: application/json' \
  -d '{"qrText":"<base64url(envelopeBytes)>"}'

# 2b. verify path — strict (authentic + recordFound + imagesMatch + metaMatch):
curl -X POST http://SERVER:3002/api/verify \
  -H 'Content-Type: application/json' \
  -d '{"qrText":"<base64url(envelopeBytes)>"}'

# 2c. verify with image upload (no scanner parsing needed — server runs ZXing):
curl -X POST http://SERVER:3002/api/verify \
  -F qrImage=@/path/to/qr-photo.png
```

Verify response:

```json
{
  "valid": true,
  "id": "uuid",
  "reason": null,
  "checks": {"authentic": true, "recordFound": true, "imagesMatch": true, "metaMatch": true},
  "meta": {"name": "...", "idNumber": "..."},
  "images": {"passportImage": "data:...;base64,...", "fingerprintImage": "data:...;base64,..."}
}
```

`reason` values: `no-qr-detected | malformed-envelope | auth-failed | unknown-record | record-missing-hashes | images-mismatch | meta-mismatch`.

Mobile flow: scan `rawBytes` → `base64url(rawBytes)` → `POST /api/verify` → render `valid` + `checks` + `images`.

---

## 5. Option A — Offline decrypt on-device

### 5.1 Android (Kotlin, ML Kit + Crypto)

Gradle:

```gradle
implementation("com.google.mlkit:barcode-scanning:17.2.0")
implementation("com.upokecenter:cbor:4.5.5") // or jackson-dataformat-cbor
```

Scan (CameraX + ML Kit — key line is `rawBytes`):

```kotlin
val scanner = BarcodeScanning.getClient(
  BarcodeScannerOptions.Builder()
    .setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
)

scanner.process(imageProxyToInputImage(proxy))
  .addOnSuccessListener { barcodes ->
    for (b in barcodes) {
      val envelopeBytes: ByteArray = b.rawBytes ?: continue // NEVER b.rawValue
      val record = EidOffline.decrypt(envelopeBytes) // § below
      showRecord(record)
      break
    }
  }
```

Decrypt:

```kotlin
import com.upokecenter.cbor.CBORObject
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

object EidOffline {
  // from server .env — inject via BuildConfig, NOT git
  private const val KEY_HEX = "9f4d1d882c86f5554ebee4b47c413d4c7b3a430e4cb9bb4b2349101187a75bd1"

  data class EidRecord(
    val v: Int, val id: String, val ts: String,
    val name: String, val idNumber: String, val fmt: String,
    val passport: ByteArray, val fingerprint: ByteArray
  )

  fun hex(s: String): ByteArray {
    require(s.length == 64) { "ENCRYPTION_KEY must be 64 hex chars" }
    return ByteArray(32) { i -> s.substring(i*2, i*2+2).toInt(16).toByte() }
  }

  fun decrypt(envelopeBytes: ByteArray): EidRecord {
    // 1. outer CBOR [v, iv, tag, ct]
    val outer = CBORObject.DecodeFromBytes(envelopeBytes)
    require(outer.size() == 4)
    val iv = outer[1].GetByteString()
    val tag = outer[2].GetByteString()
    val ct = outer[3].GetByteString()

    // 2. AES-256-GCM
    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE,
      SecretKeySpec(hex(KEY_HEX), "AES"),
      GCMParameterSpec(128, iv))
    cipher.updateAAD(ByteArray(0)) // no AAD (matches Node crypto)
    val plain = cipher.doFinal(ct + tag) // JCE wants ct||tag joined

    // 3. inner CBOR
    val inner = CBORObject.DecodeFromBytes(plain)
    val v = inner[0].AsInt32()
    return if (v == 3) {
      EidRecord(v,
        inner[1].AsString(), inner[2].AsString(),
        inner[3].AsString(), inner[4].AsString(),
        inner[5].AsString(),
        inner[6].GetByteString(), inner[7].GetByteString())
    } else if (v == 2) {
      EidRecord(v,
        inner[1].AsString(), inner[2].AsString(),
        inner[3].AsString(), inner[4].AsString(),
        "jpeg",
        inner[5].GetByteString(), inner[6].GetByteString())
    } else error("unsupported version $v")
  }

  fun dataUrl(bytes: ByteArray, fmt: String): String {
    val mime = if (fmt == "avif") "image/avif" else "image/jpeg"
    return "data:$mime;base64,${android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)}"
  }
}
```

ZXing fallback (when ML Kit gives no `rawBytes` on dense EC-L codes):

```kotlin
// com.google.zxing:core:3.5.3
val byteSegs = result.resultMetadata?.get(ResultMetadataType.BYTE_SEGMENTS) as? List<ByteArray>
val envelopeBytes: ByteArray = byteSegs?.firstOrNull()
  ?: extractByteSegmentPayload(result.rawBytes) // port of lib/qr.js below

fun extractByteSegmentPayload(raw: ByteArray): ByteArray {
  val bits = BooleanArray(raw.size * 8) { i -> ((raw[i/8].toInt() shr (7 - i%8)) and 1) == 1 }
  require(bits[0]==false && bits[1]==true && bits[2]==false && bits[3]==false) { "QR is not byte-mode" }
  for (countBits in listOf(16, 8)) {
    var count = 0
    for (i in 0 until countBits) count = (count shl 1) or (if (bits[4+i]) 1 else 0)
    val start = 4 + countBits
    if (count > 0 && start + count*8 <= bits.size) {
      return ByteArray(count) { n ->
        var v = 0
        for (j in 0 until 8) v = (v shl 1) or (if (bits[start+n*8+j]) 1 else 0)
        v.toByte()
      }
    }
  }
  error("QR byte segment has invalid length")
}
```

### 5.2 iOS (Swift, zxing-cpp + CryptoKit + CBORSwift)

Pods / SPM:

```
zxing-cpp (https://github.com/zxing-cpp/zxing-cpp) // AVFoundation stringValue can't read binary
CBORSwift / SwiftCBOR
CryptoKit (system)
```

```swift
import CryptoKit
import CBORSwift // API varies by lib — adapt decode calls
import ZXingCpp

let KEY_HEX = "9f4d1d882c86f5554ebee4b47c413d4c7b3a430e4cb9bb4b2349101187a75bd1"
// load from xcconfig / Keychain, not git

func hex(_ s: String) -> Data {
  var d = Data()
  var i = s.startIndex
  while i < s.endIndex { d.append(UInt8(s[i...s.index(i, offsetBy: 1)], radix: 16)!); i = s.index(i, offsetBy: 2) }
  return d
}

// 1. scan — raw bytes, not stringValue
let image: CGImage = /* camera frame */
let results = ZXingCpp.readBarcodes(image) // .bytes / .byteSegments
guard let envelopeBytes = results.first?.bytes else { /* keep scanning */ return }

// 2. outer CBOR [v, iv, tag, ct]
let outer = try CBOR.decode([UInt8](Data(envelopeBytes))) // -> [Int, Data, Data, Data]
let iv = outer[1] as! Data   // 12B
let tag = outer[2] as! Data  // 16B
let ct  = outer[3] as! Data

// 3. AES-GCM (CryptoKit wants nonce + combined ct||tag)
let key = SymmetricKey(data: hex(KEY_HEX))
let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ct, tag: tag)
let plain = try AES.GCM.open(box, using: key)

// 4. inner CBOR [v,id,ts,name,idNumber,fmt,passport,fingerprint]
let inner = try CBOR.decode([UInt8](plain))
// v==3: [v,id,ts,name,idNumber,fmt,passport,fingerprint]
// v==2: [v,id,ts,name,idNumber,passport,fingerprint], fmt="jpeg"
let fmt: String = (inner[0] as! Int) == 3 ? (inner[5] as! String) : "jpeg"
let passport: Data = ..., fingerprint: Data = ...
let mime = fmt == "avif" ? "image/avif" : "image/jpeg"
```

If stuck with AVFoundation only: capture still photo and `POST /api/verify` with `qrImage` multipart — server's `decodeQrImage()` (multi-width + rotation ZXing retry) handles dense codes better than client string parsing.

### 5.3 Flutter (mobile_scanner + cbor + cryptography)

```yaml
dependencies:
  mobile_scanner: ^5.0.0
  cbor: ^6.0.0
  cryptography: ^2.5.0
```

```dart
import 'package:cbor/cbor.dart';
import 'package:cryptography/cryptography.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

const keyHex = '9f4d1d882c86f5554ebee4b47c413d4c7b3a430e4cb9bb4b2349101187a75bd1';
// pass via --dart-define=EID_KEY=... in production

Uint8List hexDecode(String s) => Uint8List.fromList(
  List.generate(s.length ~/ 2, (i) => int.parse(s.substring(i*2, i*2+2), radix: 16)));

MobileScanner(
  onDetect: (capture) async {
    final Uint8List? envelopeBytes = capture.barcodes.first.rawBytes;
    if (envelopeBytes == null) return; // keep scanning — never use rawValue/displayValue
    final rec = await eidDecryptOffline(envelopeBytes);
    // render rec.passport / rec.fingerprint (avif needs a viewer plugin on some platforms)
  },
);

Future<Map<String, dynamic>> eidDecryptOffline(Uint8List envelopeBytes) async {
  final outer = cbor.decode(envelopeBytes); // [v, iv, tag, ct]
  final iv = Uint8List.fromList(List<int>.from(outer[1]));
  final tag = Uint8List.fromList(List<int>.from(outer[2]));
  final ct = Uint8List.fromList(List<int>.from(outer[3]));
  final algo = AesGcm.with256bits();
  final box = SecretBox(ct, nonce: iv, mac: Mac(tag));
  final plain = Uint8List.fromList(await algo.decrypt(
    box, secretKey: SecretKey(hexDecode(keyHex))));
  final inner = cbor.decode(plain);
  final v = inner[0] as int;
  return v == 3
    ? {'v':v,'id':inner[1],'ts':inner[2],'name':inner[3],'idNumber':inner[4],
       'fmt':inner[5],'passport':inner[6],'fingerprint':inner[7]}
    : {'v':v,'id':inner[1],'ts':inner[2],'name':inner[3],'idNumber':inner[4],
       'fmt':'jpeg','passport':inner[5],'fingerprint':inner[6]};
}
```

> AVIF thumbs: Android 12+ / iOS 16+ decode AVIF natively. For older OS or Flutter, add an AVIF plugin or ask server for JPEG thumbs.

---

## 6. Verify on-device (optional, mirrors server)

Server `verifyEnvelopeBytes()` logic — replicate if fully offline:

```pseudo
rec = offlineDecrypt(envelopeBytes)
stored = GET /api/record/:id (when online, cache hashes at enroll time)
imagesMatch = sha256(rec.passport)==stored.hashes.thumbPassport
           && sha256(rec.fingerprint)==stored.hashes.thumbFingerprint
metaMatch = stored.meta.name==rec.name && stored.meta.idNumber==rec.idNumber
valid = imagesMatch && metaMatch
```

Without server data you can only assert `authentic` (GCM tag verified). Display "authentic but unverified against registry" in that case.

---

## 7. Test plan

1. `POST /api/enroll` via `public/index.html` → copy `qrEnvelopeB64url` + `id`.
2. Unit test decrypt: `base64urlDecode(qrEnvelopeB64url)` → run §5 decrypt → compare `id` with enroll response, view images.
3. Camera test: show `public/qrcodes/<id>.png` fullscreen on monitor → scan with app → must yield same `id`. Dense high-version EC-L codes need good focus/lighting; hold steady 15–30 cm.
4. Negative tests: flip one byte → must fail GCM (`auth-failed`); scan random QR → `malformed-envelope`; enroll with new key → old QRs fail.
5. API parity: same `qrText` to `POST /api/verify` must return `valid:true` with all 4 checks.

Debug helpers:

```bash
curl http://localhost:3002/api/record/<id>          # sizes, hashes, encrypted blobs
curl -X POST http://localhost:3002/api/decrypt/<id> # server-side plaintext (dev only)
curl -X POST http://localhost:3002/api/scan \
  -H 'Content-Type: application/json' -d '{"qrText":"<b64url>"}'
```

---

## 8. Troubleshooting

- **Garbage / decrypt fails but server verify works** → you read `stringValue`, not `rawBytes`. Switch to byte API.
- **No detection on dense QR** → enable `TRY_HARDER`, auto-focus, good light; try still-photo + server `qrImage` verify (multi-scale `[orig,800,700,600,500,400,330]` + 4 rotations).
- **413 on enroll** → `envelopeBytes > 2800`. Thumbs are fixed 128px AVIF q35/q32; no client knob — reduce input or accept server-only record (`qrFitted:false`).
- **AVIF not rendering** → map `fmt` to MIME correctly; add AVIF decoder for old devices.
- **Key errors** → `ENCRYPTION_KEY` must be exactly 64 hex chars; `wrong ENCRYPTION_KEY?` from `/api/decrypt` means env mismatch.
- **Upload 413/400** → multer 5 MB cap, MIME `jpeg|png|webp|bmp` only.

---

## 9. Minimal scanner UX checklist

- [ ] Continuous scan, stop on first decodable frame (mirror `verify.html` `scanning` loop).
- [ ] Show `VALID/INVALID + reason + 4 checks` (labels: Genuine AES-GCM auth, Record on server, Images match, Name/ID match).
- [ ] Show `id`, `name`, `idNumber`, both thumbs.
- [ ] Handle `no-qr-detected` by continuing, not erroring.
- [ ] Offer "upload QR photo" fallback (`POST /api/verify` multipart `qrImage`).
- [ ] Never log the key or full plaintext blobs.
