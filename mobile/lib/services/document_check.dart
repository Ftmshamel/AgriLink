import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';

/// Something about an uploaded requirement that a reviewer should look at.
///
/// These are **screening signals, not proof**. No check here can tell a forged
/// Barangay Certificate from a real one — that judgement stays with the
/// superadmin. What they do catch is the cheap kind of abuse: a blank photo, a
/// screenshot of nothing, a thumbnail too small to read, or the same picture
/// submitted for every requirement.
enum DocumentFlag {
  tooSmall(
    'Very low resolution',
    'Too small to read a document from. A photographed requirement is normally '
        'over a thousand pixels wide.',
  ),
  tooLightweight(
    'Unusually small file',
    'Far lighter than a photo of a real document, which suggests a graphic or '
        'a thumbnail rather than a camera shot.',
  ),
  nearlyBlank(
    'Almost blank',
    'Nearly one flat colour, so there is no document visible in it.',
  ),
  lowDetail(
    'Very little detail',
    'Only a handful of colours. This looks like a drawing, a screenshot, or a '
        'plain image rather than a photographed document.',
  ),
  reusedInSameApplication(
    'Same image used twice',
    'Identical to another file in this application, so one requirement is '
        'standing in for another.',
  ),
  reusedByAnotherAccount(
    'Already uploaded by another account',
    'Byte-for-byte identical to a file submitted by a different applicant.',
  );

  const DocumentFlag(this.label, this.explanation);

  final String label;
  final String explanation;

  static DocumentFlag? parse(String value) {
    for (final flag in DocumentFlag.values) {
      if (flag.name == value) return flag;
    }
    return null;
  }
}

/// The measurements taken of one uploaded file.
class DocumentInspection {
  const DocumentInspection({
    required this.width,
    required this.height,
    required this.byteLength,
    required this.contentHash,
    required this.flags,
  });

  final int width;
  final int height;
  final int byteLength;

  /// SHA-256 of the raw bytes, used to spot the same picture submitted twice.
  final String contentHash;
  final List<DocumentFlag> flags;

  bool get looksSuspicious => flags.isNotEmpty;
}

/// Screens uploaded requirement photos for the obvious kinds of nonsense.
class DocumentCheck {
  /// A phone photo of a document is normally well over this on its short edge.
  static const minimumEdge = 500;

  /// Below this, the file is too light to be a camera photo of paper.
  static const minimumBytes = 25000;

  /// Luminance spread below which an image is effectively one flat colour.
  static const blankStdDev = 12.0;

  /// Distinct brightness levels below which there is almost nothing in the
  /// image. Measured on luminance rather than colour, because a greyscale scan
  /// of a real document is perfectly normal and must not be flagged for it.
  static const lowDetailLevels = 8;

  static String hashOf(Uint8List bytes) => sha256.convert(bytes).toString();

  /// Decodes [bytes] and measures them. Returns dimensions of zero when the
  /// bytes are not a readable image at all.
  static Future<DocumentInspection> inspect(Uint8List bytes) async {
    final hash = hashOf(bytes);
    int width = 0;
    int height = 0;
    Uint8List? rgba;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      width = image.width;
      height = image.height;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      rgba = data?.buffer.asUint8List();
      image.dispose();
      codec.dispose();
    } catch (_) {
      // Undecodable bytes are reported through the size flags below.
    }

    return DocumentInspection(
      width: width,
      height: height,
      byteLength: bytes.length,
      contentHash: hash,
      flags: measure(
        width: width,
        height: height,
        byteLength: bytes.length,
        rgba: rgba,
      ),
    );
  }

  /// The judgement itself, separated from decoding so it can be tested with
  /// plain pixel buffers.
  static List<DocumentFlag> measure({
    required int width,
    required int height,
    required int byteLength,
    Uint8List? rgba,
  }) {
    final flags = <DocumentFlag>[];
    final shortEdge = width < height ? width : height;
    if (width == 0 || height == 0 || shortEdge < minimumEdge) {
      flags.add(DocumentFlag.tooSmall);
    }
    if (byteLength < minimumBytes) {
      flags.add(DocumentFlag.tooLightweight);
    }
    if (rgba == null || rgba.length < 4) return flags;

    // Sample a grid rather than every pixel: a 1400 x 1900 photo is ten million
    // bytes, and the answer does not improve for reading all of them. The
    // stride is forced odd so that a regular pattern in the image — a scanline,
    // a checkerboard — cannot align with it and be sampled as a flat colour.
    final pixels = rgba.length ~/ 4;
    final step = pixels <= 20000 ? 1 : (pixels ~/ 20000) | 1;
    final levels = <int>{};
    var sum = 0.0;
    var sumSquares = 0.0;
    var counted = 0;

    for (var index = 0; index < pixels; index += step) {
      final offset = index * 4;
      final r = rgba[offset];
      final g = rgba[offset + 1];
      final b = rgba[offset + 2];
      // Rec. 601 luminance, which is close enough to how bright a pixel looks.
      final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
      sum += luminance;
      sumSquares += luminance * luminance;
      counted++;
      // Quantise to 32 brightness steps so sensor noise does not read as
      // detail, while a genuinely shaded photograph still spans many steps.
      levels.add(luminance.round() >> 3);
    }
    if (counted == 0) return flags;

    final mean = sum / counted;
    final variance = (sumSquares / counted) - (mean * mean);
    final stdDev = variance <= 0 ? 0.0 : _sqrt(variance);

    if (stdDev < blankStdDev) flags.add(DocumentFlag.nearlyBlank);
    if (levels.length < lowDetailLevels) flags.add(DocumentFlag.lowDetail);
    return flags;
  }

  static double _sqrt(double value) {
    var guess = value;
    for (var i = 0; i < 24; i++) {
      guess = 0.5 * (guess + value / guess);
    }
    return guess;
  }

  /// Encodes flags for storage on the verification-file document.
  static List<String> encode(List<DocumentFlag> flags) =>
      flags.map((flag) => flag.name).toList();

  static List<DocumentFlag> decode(Object? stored) {
    if (stored is! List) return const [];
    return [
      for (final value in stored)
        if (DocumentFlag.parse('$value') case final flag?) flag,
    ];
  }

  /// Human summary used in the review queue.
  static String summarise(List<DocumentFlag> flags) {
    if (flags.isEmpty) return 'No screening warnings';
    if (flags.length == 1) return flags.single.label;
    return '${flags.first.label} +${flags.length - 1} more';
  }
}

/// Convenience for the signup form: hashes without decoding, so repeated files
/// inside one application can be spotted before anything is uploaded.
String quickHash(List<int> bytes) => sha256.convert(bytes).toString();

/// Kept for documents stored as base64 in Firestore.
String hashBase64(String base64Content) =>
    sha256.convert(base64Decode(base64Content)).toString();
