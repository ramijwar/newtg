import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Media URLs are immutable because every stored upload has its own public ID.
/// The persistent disk cache therefore reuses an image until its media ID
/// changes; an unchanged product/store/listing image is not fetched again.
final class CachedMediaImage extends StatelessWidget {
  const CachedMediaImage({
    super.key,
    required this.mediaPublicId,
    this.fit = BoxFit.cover,
    this.errorIcon = Icons.image_not_supported_outlined,
  });

  final String mediaPublicId;
  final BoxFit fit;
  final IconData errorIcon;

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
    imageUrl: AppConfig.mediaUrl(mediaPublicId),
    cacheKey: 'media-$mediaPublicId',
    fit: fit,
    fadeInDuration: const Duration(milliseconds: 120),
    placeholder: (_, _) => const ColoredBox(
      color: Color(0xFFE7EEE9),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    ),
    errorWidget: (_, _, _) => ColoredBox(
      color: const Color(0xFFE7EEE9),
      child: Center(child: Icon(errorIcon)),
    ),
  );
}
