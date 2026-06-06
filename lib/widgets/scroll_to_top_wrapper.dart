import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ScrollToTopWrapper extends StatefulWidget {
  const ScrollToTopWrapper({
    super.key,
    required this.scrollController,
    required this.child,
    this.bottomOffset = 0.0,
  });

  final ScrollController scrollController;
  final Widget child;
  final double bottomOffset;

  @override
  State<ScrollToTopWrapper> createState() => _ScrollToTopWrapperState();
}

class _ScrollToTopWrapperState extends State<ScrollToTopWrapper> {
  bool _showScrollToTop = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            final double offset = widget.scrollController.hasClients ? widget.scrollController.offset : 0.0;
            if (offset > 200 && notification.direction == ScrollDirection.reverse) {
              if (!_showScrollToTop) {
                setState(() {
                  _showScrollToTop = true;
                });
              }
            } else if (notification.direction == ScrollDirection.forward || offset <= 200) {
              if (_showScrollToTop) {
                setState(() {
                  _showScrollToTop = false;
                });
              }
            }
            return false;
          },
          child: widget.child,
        ),
        Positioned(
          right: 16,
          bottom: widget.bottomOffset + 16,
          child: AnimatedScale(
            scale: _showScrollToTop ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedOpacity(
              opacity: _showScrollToTop ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: FloatingActionButton.small(
                heroTag: null,
                onPressed: () {
                  widget.scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                  );
                },
                child: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
