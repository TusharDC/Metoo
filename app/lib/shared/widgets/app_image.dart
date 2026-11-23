import 'package:flutter/material.dart';

/// Network image helpers used app-wide.
///
/// We use Flutter's built-in Image.network / NetworkImage rather than
/// cached_network_image because the latter fails to decode cross-origin images
/// on Flutter Web (ImageCodecException). Image.network uses the browser's native
/// decode path on web and works on mobile too.
Widget appNetworkImage(String url, {BoxFit? fit, double? width, double? height}) {
  return Image.network(
    url,
    fit: fit,
    width: width,
    height: height,
    gaplessPlayback: true,
    loadingBuilder: (context, child, progress) =>
        progress == null ? child : const ColoredBox(color: Colors.black12),
    errorBuilder: (context, error, stack) =>
        const ColoredBox(color: Colors.black12, child: Icon(Icons.broken_image)),
  );
}

/// ImageProvider variant (for CircleAvatar.backgroundImage, DecorationImage, etc.).
ImageProvider appImageProvider(String url) => NetworkImage(url);
