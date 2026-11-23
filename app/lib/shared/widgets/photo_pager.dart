import 'package:flutter/material.dart';

import 'app_image.dart';

/// Tappable photo carousel: tap left/right thirds to page, dots show position.
class PhotoPager extends StatefulWidget {
  final List<String> urls;
  const PhotoPager({super.key, required this.urls});
  @override
  State<PhotoPager> createState() => _PhotoPagerState();
}

class _PhotoPagerState extends State<PhotoPager> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.person, size: 96)),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        appNetworkImage(widget.urls[_i], fit: BoxFit.cover),
        Row(
          children: [
            Expanded(child: GestureDetector(onTap: _prev, behavior: HitTestBehavior.translucent)),
            Expanded(child: GestureDetector(onTap: _next, behavior: HitTestBehavior.translucent)),
          ],
        ),
        if (widget.urls.length > 1)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              children: List.generate(
                widget.urls.length,
                (k) => Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: k == _i ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _prev() => setState(() => _i = (_i - 1).clamp(0, widget.urls.length - 1));
  void _next() => setState(() => _i = (_i + 1).clamp(0, widget.urls.length - 1));
}
