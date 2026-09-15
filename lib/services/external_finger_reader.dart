import 'dart:typed_data';

/// Seam for an EXTERNAL fingerprint reader (USB-OTG / Bluetooth scanner
/// + ISO 19794-2 matcher SDK, e.g. Innovatrics/Neurotech, or a server
/// `bozorth3` endpoint mirroring the face flow).
///
/// The phone's own fingerprint sensor is deliberately NOT used: it only
/// authenticates the device owner and cannot 1:1-match a live finger
/// against the QR's FMR. Fingerprint is an OPTIONAL step — the card
/// opens on QR-valid + face-match alone.
///
/// To integrate a reader SDK, implement [ExternalFingerprintReader] with
/// the vendor plugin (capture bytes + match against [qrFmr]) and pass it
/// to the external-reader screen. Until then [UnimplementedReader]
/// explains the state instead of faking a match.
abstract class ExternalFingerprintReader {
  /// Captures a live finger sample. Throws [ReaderNotConnected] when no
  /// reader is attached.
  Future<FingerSample> capture();

  /// 1:1 match of [sample] vs the QR's FMR bytes. Returns 0..1
  /// (higher = more similar) with the SDK's recommended threshold.
  Future<FingerMatch> match(FingerSample sample, Uint8List qrFmr);
}

class FingerSample {
  const FingerSample(this.bytes, {this.format = 'iso-19794-2'});
  final Uint8List bytes;
  final String format;
}

class FingerMatch {
  const FingerMatch({
    required this.score,
    required this.threshold,
    required this.matched,
    this.backend = 'external-reader',
  });

  final double score;
  final double threshold;
  final bool matched;
  final String backend;
}

class ReaderNotConnected implements Exception {
  const ReaderNotConnected([this.detail = 'No external reader attached.']);
  final String detail;

  @override
  String toString() => 'ReaderNotConnected: $detail';
}

/// Placeholder until a vendor SDK is integrated — always reports missing
/// hardware instead of a fabricated verdict.
class UnimplementedReader implements ExternalFingerprintReader {
  const UnimplementedReader();

  @override
  Future<FingerSample> capture() async {
    throw const ReaderNotConnected(
        'OTG reader SDK not integrated — see ExternalFingerprintReader.');
  }

  @override
  Future<FingerMatch> match(FingerSample sample, Uint8List qrFmr) {
    throw const ReaderNotConnected(
        'OTG reader SDK not integrated — see ExternalFingerprintReader.');
  }
}
