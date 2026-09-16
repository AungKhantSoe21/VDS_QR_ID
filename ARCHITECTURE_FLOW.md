# eID Verify — Architecture Flow

## High-Level User Journey

```mermaid
flowchart TD
    A([App Launch]) --> B[SplashScreen]
    B --> C[HomeScreen<br/>Bottom Nav]
    C --> D[ScannerScreen]
    C --> E[SettingsScreen]
    D --> F{QR Detected}
    F -->|MOSIP Claim 169| G[MOSIP Offline Verify]
    F -->|Legacy v2/v3| H[Legacy CBOR Decrypt]
    F -->|Invalid| I[Error: Not a valid eID QR]
    G -->|Valid| J[FaceVerifyScreen]
    G -->|Invalid| I
    H -->|Valid| J
    H -->|Invalid| I
    J --> K{Face Check}
    K -->|Auto Mode<br/>faceHash present| L[Dual-Model Match]
    K -->|Visual Mode<br/>no faceHash| M[Side-by-side Compare]
    L -->|Match| N[SmartCardScreen]
    L -->|Mismatch| O[Error Card]
    L -->|No Face| O
    M --> N
    N --> P{Optional: Fingerprint}
    P -->|Tap button| Q[ExternalReaderScreen]
    P -->|Skip| R[Done - Scan Next]
    Q -->|Match/Mismatch| N
```

## App Startup (Cold Boot)

```mermaid
flowchart TD
    Start([main.dart]) --> Bind[WidgetsFlutterBinding.ensureInitialized]
    Bind --> Run[runApp QrIdentityApp]
    Run --> Splash[SplashScreen._boot]

    subgraph Startup ["AppStartup.run — 3 stages, failure-tolerant"]
        S1[Stage 1: Config<br/>Load .env] --> S2[Stage 2: Preferences<br/>SharedPreferences → threshold, theme, language]
        S2 --> S3[Stage 3: Face Models<br/>Hash-verify cached ONNX files]
        S3 --> Done[StartupSummary<br/>modelsReady]
    end

    Splash --> Startup
    Startup --> Timeout{5s timeout?}
    Timeout -->|Yes| Nav[Fade to HomeScreen]
    Timeout -->|No + minHold 1.2s| Nav
    Nav --> Home[HomeScreen with Scanner tab active]
```

## QR Scanning — v14+ Signed-Only

```mermaid
flowchart TD
    Scan([ScannerScreen._attemptCapture]) --> Cooldown{2s cooldown?}
    Cooldown -->|Yes| Skip[Skip — cooling down]
    Cooldown -->|No| Extract[Extract barcode text]

    Extract --> Detect{isMosipQrText?}
    Detect -->|Base45 chars, 100–4296 chars| MOSIP[MOSIP Path]
    Detect -->|Neither| Fail[Error: Unreadable QR]

    subgraph MOSIP ["MOSIP Claim 169 Pipeline (v14+)"]
        M1[Base45 Decode] --> M2[zlib Inflate]
        M2 --> M3[CBOR Decode → Tag 18 COSE_Sign1]
        M3 --> M4[EdDSA Verify<br/>pinned Ed25519 public key]
        M4 --> M5{Signature valid?}
        M5 -->|Yes| M6{Expired?}
        M5 -->|No| M7[Error: auth-failed]
        M6 -->|No| M8[MosipCredential extracted<br/>name, dob, faceHash, fmr]
        M6 -->|Yes| M9[Error: expired]
    end

    MOSIP -->|Valid| Next[Push FaceVerifyScreen<br/>CardData.fromMosip]
```

## Face Verification — Dual-Model Pipeline

```mermaid
flowchart TD
    Face([FaceVerifyScreen]) --> Mode{faceHash present?<br/>Auto or Visual mode}

    Mode -->|Auto| Capture[Capture Selfie<br/>front camera, 1024px, q85]
    Mode -->|Visual| Capture

    Capture --> Selfie{Photo taken?}
    Selfie -->|No| Back[Return to idle]
    Selfie -->|Yes| AutoCheck{Auto mode?}

    AutoCheck -->|Yes| MatchFlow
    AutoCheck -->|No| Visual[Show QR photo vs Selfie<br/>side-by-side]

    subgraph MatchFlow ["FaceMatcher.matchSelfieVsQr"]
        MF1[Open OrtFaceEngine<br/>SCRFD + EdgeFace-S + w600k_mbf] --> MF2[Decode selfie → RGB]
        MF2 --> MF3[SCRFD-500M Detect<br/>640×640 letterbox, thresh 0.5, NMS 0.4]
        MF3 --> MF4[Largest face selected]
        MF4 --> MF5[Similarity Align → 112×112<br/>ArcFace landmark template]
        MF5 --> MF6[EdgeFace-S Embed → 512-d L2-norm]
        MF5 --> MF7[w600k_mbf Embed → 512-d L2-norm]

        MF6 --> MF8{QR template version?}
        MF7 --> MF8

        MF8 -->|v3 68B| MF9[Project 512→64-d<br/>Cosine similarity vs template]
        MF8 -->|v2 132B| MF10[Project 512→128-d<br/>Cosine similarity vs template]
        MF8 -->|v1 65B hash| MF11[Sign-hash comparison<br/>1 - hamming/512]

        MF9 --> MF12[pickMatch<br/>Better margin above threshold wins]
        MF10 --> MF12
        MF11 --> MF12
    end

    MF12 --> Result{Match result?}
    Result -->|Match| ShowCard[Show "Show Card" button]
    Result -->|Mismatch| ErrCard[Error: Score below threshold]
    Result -->|NoFace| ErrFace[Error: No face detected]

    ShowCard --> OpenCard[Push SmartCardScreen]
    Visual --> OpenCard
    ErrCard --> Retry[Retry or retake]
    ErrFace --> Retry
```

## Face Model Pack — On-Device Setup

```mermaid
flowchart TD
    Pack([FaceModelPack]) --> Ready{Models cached + SHA-verified?}
    Ready -->|Yes| OK[Ready — no work needed]
    Ready -->|No| Bundle{APK bundle available?}

    Bundle -->|Yes| Copy[Copy from assets/models/<br/>det_500m.onnx 2.5MB<br/>edgeface_s.onnx 14.8MB<br/>w600k_mbf.onnx 13.6MB]
    Copy --> SHA{SHA-256 match?}
    SHA -->|Yes| OK
    SHA -->|No| Download[Download with resume<br/>Mirror retries × 3]

    Bundle -->|No| Download
    Download --> Resume{.part file exists?}
    Resume -->|Yes| Range[HTTP Range resume]
    Resume -->|No| Fresh[Fresh download]
    Range --> Verify[SHA-256 verify]
    Fresh --> Verify
    Verify -->|Match| Rename[Rename .part → final]
    Verify -->|Mismatch| Delete[Delete .part, retry]
    Delete --> Download
    Rename --> OK

    subgraph Models ["3 ONNX Models (~31MB)"]
        DET[det_500m.onnx<br/>SCRFD face detector]
        REC[edgeface_s.onnx<br/>EdgeFace-S recognition]
        LEG[w600k_mbf.onnx<br/>ArcFace buffalo legacy]
    end
```

## Smart Card Display

```mermaid
flowchart TD
    Card([SmartCardScreen]) --> Flip[SmartCardFlip widget<br/>NRC-style double-sided card]

    Flip --> Front[Front Side<br/>Name, UID No., National Reg<br/>DOB, Issuer, Expiry]
    Flip --> Back[Back Side<br/>QR text payload<br/>Biometric note<br/>Verification badges]

    Card --> Badges{Verification status}
    Badges --> FaceBadge[Face Match / Mismatch badge]
    Badges --> VisualBadge[Visual Check badge]
    Badges --> FingerBadge[Fingerprint badge]

    Card --> Actions
    Actions --> FlipBtn[Flip Card button]
    Actions --> ScanBtn[Scan Next — pop to root]
    Actions --> FingerBtn[Optional: Fingerprint check]

    FingerBtn --> ExtReader[Push ExternalReaderScreen]
    ExtReader --> FMR[Read FMR from credential<br/>ISO 19794-2]
    FMR --> Compare[Compare vs live scan<br/>if reader available]
    Compare --> FingerResult[Match / Mismatch badge]
```

## Settings & Preferences

```mermaid
flowchart TD
    Settings([SettingsScreen]) --> Theme[Theme Mode<br/>Light / Dark / System]
    Settings --> Lang[Language<br/>Burmese (default) / English]
    Settings --> Threshold[Face Match Threshold<br/>Slider 0.0–1.0<br/>Default: 0.60]
    Settings --> Models[Face Models<br/>Status / Setup / Clear]

    Theme --> |Save| ThemeCtrl[ThemeController.instance<br/>Notifies MaterialApp]
    Lang --> |Save| LangCtrl[LanguageController.instance<br/>Bilingual UI strings]
    Threshold --> |Save| Prefs[SharedPreferences<br/>FaceMatcher.hashThreshold]
    Models --> |Setup| Pack[FaceModelPack.ensureReady<br/>Copy from bundle]
    Models --> |Clear| Clear[FaceModelPack.clear<br/>Delete cached ONNX files]
```

## Service Layer Architecture

```mermaid
flowchart LR
    subgraph Screens ["Screens"]
        Splash
        Home
        Scanner
        FaceVerify
        SmartCard
        Settings
        ExtReader
    end

    subgraph Services ["Services"]
        AppStartup
        Mosip[verifyQrTextOffline]
        FaceMatcher
        FaceEmbedder[OrtFaceEngine]
        FaceProjection
        FaceModelPack
        ExtFinger[ExternalFingerReader]
    end

    subgraph Config ["Config"]
        Issuer[IssuerPin<br/>Ed25519 pubkey]
    end

    subgraph Models ["Models"]
        CardData
        MosipCredential
    end

    Scanner --> Mosip
    Mosip --> Issuer
    FaceVerify --> FaceMatcher
    FaceMatcher --> FaceEmbedder
    FaceMatcher --> FaceProjection
    FaceEmbedder --> FaceModelPack
    SmartCard --> ExtFinger
    AppStartup --> FaceModelPack

    Scanner --> CardData
    Mosip --> MosipCredential
    EidParser --> EidRecord
    MosipCredential --> CardData
    EidRecord --> CardData
```

## Error Handling Flow

```mermaid
flowchart TD
    Error([FormatException thrown]) --> Msg{Error message}

    Msg -->|malformed-envelope| DecodeErr[CBOR decode failed<br/>→ Invalid QR format]
    Msg -->|auth-failed| CryptoErr[AES-GCM tag mismatch<br/>→ Wrong key or tampered]
    Msg -->|expired| ExpErr[QR past expiry date<br/>→ Re-enroll needed]
    Msg -->|not-yet-valid| TimeErr[Device clock skew<br/>→ Check system time]
    Msg -->|unknown-key| KeyErr[Issuer key rotated<br/>→ Re-pin issuer key]
    Msg -->|unsupported-legacy-qr| LegErr[Old QR format<br/>→ Re-enroll]
    Msg -->|unsupported-version| VerErr[CBOR payload version<br/>→ v2/v3 only]
    Msg -->|empty detection| EmptyErr[No bytes or text<br/>→ Focus camera]

    CryptoErr --> Hint["'Signed by unknown issuer...' or<br/>'Signature/decrypt failed...'"]
    ExpErr --> Hint2["'QR expired — re-enroll...'"]
    EmptyErr --> Hint3["'Hold steady 15-30cm,<br/>improve focus/light'"]
```
