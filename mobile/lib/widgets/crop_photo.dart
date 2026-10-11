import 'dart:convert';

import 'package:flutter/material.dart';

import '../app.dart';
import '../utils/app_colors.dart';

/// A crop's photo filling its parent, or a plain placeholder when there is
/// none yet. Order screens only know the crop id, so they pass [cropId] and
/// the photo is looked up from the listing.
class CropPhoto extends StatelessWidget {
  const CropPhoto({
    super.key,
    this.photoBase64,
    this.cropId = '',
    this.iconSize = 24,
  });

  final String? photoBase64;
  final String cropId;
  final double iconSize;

  /// Photos are large and rarely change, so each is fetched once per run.
  /// Misses are dropped so a photo the farmer adds later still turns up.
  static final _cache = <String, Future<String?>>{};

  static Future<String?> _lookup(String cropId) =>
      _cache.putIfAbsent(cropId, () async {
        try {
          final crop =
              await authService.database.getDocument('mobileCrops', cropId);
          final photo = crop?['photoBase64'];
          if (photo is String && photo.isNotEmpty) return photo;
        } catch (_) {}
        _cache.remove(cropId);
        return null;
      });

  @override
  Widget build(BuildContext context) {
    final photo = photoBase64;
    if (photo != null && photo.isNotEmpty) return _image(photo);
    if (cropId.isEmpty) return _placeholder();
    return FutureBuilder<String?>(
      future: _lookup(cropId),
      builder: (context, snapshot) {
        final found = snapshot.data;
        return found == null ? _placeholder() : _image(found);
      },
    );
  }

  Widget _image(String photo) => Image.memory(
        base64Decode(photo),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(),
      );

  Widget _placeholder() => Container(
        width: double.infinity,
        height: double.infinity,
        color: canvas,
        alignment: Alignment.center,
        child: Icon(Icons.image_outlined, color: muted, size: iconSize),
      );
}

/// Small rounded [CropPhoto] for order and cart rows.
class CropThumb extends StatelessWidget {
  const CropThumb({super.key, this.photoBase64, this.cropId = ''});

  final String? photoBase64;
  final String cropId;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 52,
        height: 52,
        child: CropPhoto(photoBase64: photoBase64, cropId: cropId),
      ),
    );
  }
}
