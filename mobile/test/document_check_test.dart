import 'dart:typed_data';

import 'package:agrilink_mobile/services/document_check.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a raw RGBA buffer of [width] x [height].
///
/// [shade] returns the grey level for a pixel index, which is enough to model
/// a blank photo, a two-tone graphic, or a noisy camera shot.
Uint8List pixels(int width, int height, int Function(int index) shade) {
  final buffer = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    final value = shade(i).clamp(0, 255);
    buffer[i * 4] = value;
    buffer[i * 4 + 1] = value;
    buffer[i * 4 + 2] = value;
    buffer[i * 4 + 3] = 255;
  }
  return buffer;
}

/// Stands in for a real photograph: plenty of size, weight, and variation.
List<DocumentFlag> measurePhoto(Uint8List rgba, {int width = 1200, int height = 1600}) =>
    DocumentCheck.measure(
      width: width,
      height: height,
      byteLength: 400000,
      rgba: rgba,
    );

void main() {
  group('screening accepts a plausible document photo', () {
    test('a detailed, well-sized photo raises nothing', () {
      // Varied greys across the whole range, as a photographed page would be.
      final rgba = pixels(300, 300, (i) => (i * 7) % 256);
      expect(measurePhoto(rgba), isEmpty);
    });
  });

  group('screening catches obvious rubbish', () {
    test('a blank image is flagged as nearly blank and low detail', () {
      final rgba = pixels(300, 300, (_) => 255);
      final flags = measurePhoto(rgba);
      expect(flags, contains(DocumentFlag.nearlyBlank));
      expect(flags, contains(DocumentFlag.lowDetail));
    });

    test('a flat colour with faint noise is still nearly blank', () {
      final rgba = pixels(300, 300, (i) => 128 + (i % 3));
      expect(measurePhoto(rgba), contains(DocumentFlag.nearlyBlank));
    });

    test('a two-tone graphic is flagged as low detail', () {
      // A checkerboard: high contrast, but only two brightness levels.
      final rgba = pixels(
        300,
        300,
        (i) => ((i ~/ 300) + (i % 300)) % 2 == 0 ? 0 : 255,
      );
      final flags = measurePhoto(rgba);
      expect(flags, contains(DocumentFlag.lowDetail));
      expect(flags, isNot(contains(DocumentFlag.nearlyBlank)));
    });

    test('a greyscale scan is not mistaken for a flat graphic', () {
      // Black-and-white scans are ordinary; only the brightness varies, and
      // that must not read as "no detail".
      final rgba = pixels(400, 400, (i) => (i * 13) % 256);
      expect(measurePhoto(rgba), isEmpty);
    });

    test('a thumbnail is too small to read', () {
      final rgba = pixels(60, 60, (i) => (i * 7) % 256);
      final flags = DocumentCheck.measure(
        width: 60,
        height: 60,
        byteLength: 400000,
        rgba: rgba,
      );
      expect(flags, contains(DocumentFlag.tooSmall));
    });

    test('a tall but narrow image is judged on its short edge', () {
      final rgba = pixels(200, 200, (i) => (i * 7) % 256);
      final flags = DocumentCheck.measure(
        width: 100,
        height: 4000,
        byteLength: 400000,
        rgba: rgba,
      );
      expect(flags, contains(DocumentFlag.tooSmall));
    });

    test('a file far too light to be a camera photo is flagged', () {
      final rgba = pixels(300, 300, (i) => (i * 7) % 256);
      final flags = DocumentCheck.measure(
        width: 1200,
        height: 1600,
        byteLength: 4000,
        rgba: rgba,
      );
      expect(flags, contains(DocumentFlag.tooLightweight));
    });

    test('undecodable bytes still report what can be measured', () {
      final flags = DocumentCheck.measure(
        width: 0,
        height: 0,
        byteLength: 900,
        rgba: null,
      );
      expect(flags, contains(DocumentFlag.tooSmall));
      expect(flags, contains(DocumentFlag.tooLightweight));
    });
  });

  group('duplicate detection', () {
    test('identical bytes hash the same, different bytes do not', () {
      final a = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b = Uint8List.fromList([1, 2, 3, 4, 5]);
      final c = Uint8List.fromList([1, 2, 3, 4, 6]);
      expect(DocumentCheck.hashOf(a), DocumentCheck.hashOf(b));
      expect(DocumentCheck.hashOf(a), isNot(DocumentCheck.hashOf(c)));
      expect(DocumentCheck.hashOf(a).length, 64);
    });
  });

  group('storage round trip', () {
    test('flags survive being written to and read back from Firestore', () {
      const flags = [DocumentFlag.nearlyBlank, DocumentFlag.tooSmall];
      final encoded = DocumentCheck.encode(flags);
      expect(encoded, ['nearlyBlank', 'tooSmall']);
      expect(DocumentCheck.decode(encoded), flags);
    });

    test('unknown or missing values decode to nothing', () {
      expect(DocumentCheck.decode(null), isEmpty);
      expect(DocumentCheck.decode(['somethingElse']), isEmpty);
      expect(DocumentCheck.decode('not a list'), isEmpty);
    });

    test('the review summary stays short', () {
      expect(DocumentCheck.summarise([]), 'No screening warnings');
      expect(
        DocumentCheck.summarise([DocumentFlag.nearlyBlank]),
        'Almost blank',
      );
      expect(
        DocumentCheck.summarise(
          [DocumentFlag.nearlyBlank, DocumentFlag.tooSmall],
        ),
        'Almost blank +1 more',
      );
    });
  });
}
