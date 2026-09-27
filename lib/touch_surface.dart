import 'dart:async';

import 'package:flutter/material.dart';

import 'design.dart';

class TouchSurface extends StatefulWidget {
  final double height, sensitivity;
  final bool dragging;
  final ValueChanged<String> onAction;
  const TouchSurface({
    super.key,
    required this.height,
    required this.sensitivity,
    required this.dragging,
    required this.onAction,
  });
  @override
  State<TouchSurface> createState() => _TouchSurfaceState();
}

class _TouchSurfaceState extends State<TouchSurface> {
  Offset cursor = const Offset(.5, .5);
  String? pressed;
  bool scrolling = false;
  late bool dragging = widget.dragging;
  double wheelOffset = 0;
  Timer? reveal, fade;
  void armScroll() {
    fade?.cancel();
    if (scrolling || reveal?.isActive == true) return;
    reveal = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => scrolling = true);
    });
  }

  void leaveScroll() {
    reveal?.cancel();
    fade?.cancel();
    fade = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => scrolling = false);
    });
  }

  @override
  void dispose() {
    reveal?.cancel();
    fade?.cancel();
    super.dispose();
  }

  Widget clickZone(String side) => Expanded(
    child: Semantics(
      button: true,
      label: side == 'left' ? 'Chuột trái' : 'Chuột phải',
      child: GestureDetector(
        key: ValueKey('mouse-$side'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => pressed = side),
        onTapCancel: () => setState(() => pressed = null),
        onTapUp: (_) => setState(() => pressed = null),
        onTap: () =>
            widget.onAction(side == 'left' ? 'Nhấp trái' : 'Nhấp phải'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: pressed == side
                ? Colors.white.withValues(alpha: .07)
                : Colors.transparent,
            border: Border.all(
              color: pressed == side ? Colors.white38 : Colors.transparent,
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Container(
      height: widget.height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: panelGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: dragging ? mint : const Color(0xFF293D57),
          width: 2,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onAction('Nhấp trái'),
              onDoubleTap: () => widget.onAction('Nhấp đúp'),
              onPanUpdate: (details) {
                setState(
                  () => cursor = Offset(
                    (cursor.dx +
                            details.delta.dx *
                                widget.sensitivity /
                                bounds.maxWidth)
                        .clamp(.04, .9),
                    (cursor.dy +
                            details.delta.dy *
                                widget.sensitivity /
                                widget.height)
                        .clamp(.04, .85),
                  ),
                );
                widget.onAction(dragging ? 'Đang kéo' : 'Di chuyển con trỏ');
              },
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      color: Colors.white24,
                      size: 36,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Không gian chạm',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: cursor.dx * bounds.maxWidth,
            top: cursor.dy * widget.height,
            child: const IgnorePointer(
              child: Icon(Icons.near_me_rounded, color: mint, size: 25),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            height: 52,
            child: Row(
              children: [
                clickZone('left'),
                const SizedBox(width: 6),
                clickZone('right'),
              ],
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: IconButton(
              tooltip: dragging ? 'Thả chuột' : 'Bật kéo thả',
              isSelected: dragging,
              style: IconButton.styleFrom(
                foregroundColor: Colors.white54,
                backgroundColor: dragging
                    ? mint.withValues(alpha: .12)
                    : Colors.transparent,
              ),
              icon: const Icon(Icons.open_with_rounded, size: 20),
              selectedIcon: const Icon(
                Icons.open_with_rounded,
                size: 20,
                color: mint,
              ),
              onPressed: () {
                setState(() => dragging = !dragging);
                widget.onAction(
                  dragging
                      ? 'Đang giữ chuột trái · di ngón tay để kéo'
                      : 'Đã thả chuột',
                );
              },
            ),
          ),
          Positioned(
            top: 12,
            right: 6,
            bottom: 68,
            width: 44,
            child: MouseRegion(
              onEnter: (_) => armScroll(),
              onExit: (_) => leaveScroll(),
              child: Listener(
                onPointerDown: (_) => armScroll(),
                onPointerUp: (_) => leaveScroll(),
                onPointerCancel: (_) => leaveScroll(),
                child: GestureDetector(
                  key: const ValueKey('scroll-strip'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    if (scrolling) {
                      fade?.cancel();
                      if (details.delta.dy != 0) {
                        setState(
                          () => wheelOffset =
                              (wheelOffset + details.delta.dy) % 8,
                        );
                        widget.onAction(
                          details.delta.dy > 0 ? 'Cuộn xuống' : 'Cuộn lên',
                        );
                      }
                    }
                  },
                  onVerticalDragEnd: (_) => leaveScroll(),
                  child: AnimatedOpacity(
                    opacity: scrolling ? 1 : .08,
                    duration: const Duration(milliseconds: 250),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: double.infinity,
                        child: CustomPaint(painter: _WheelPainter(wheelOffset)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _WheelPainter extends CustomPainter {
  final double offset;
  _WheelPainter(this.offset);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // A recessed track surrounds the long cylindrical wheel.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(16)),
      Paint()..color = const Color(0xFF091321),
    );
    final wheel = rect.deflate(4);
    final shape = RRect.fromRectAndRadius(wheel, const Radius.circular(11));
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFF243A51),
            Color(0xFF7893AB),
            Color(0xFF3B566D),
            Color(0xFF1B3047),
          ],
          stops: [0, .35, .7, 1],
        ).createShader(wheel),
    );
    canvas.save();
    canvas.clipRRect(shape);
    final ridge = Paint()
      ..color = Colors.white.withValues(alpha: .23)
      ..strokeWidth = 1;
    for (double y = -8 + offset; y < size.height + 8; y += 8) {
      canvas.drawLine(Offset(7, y), Offset(size.width - 7, y), ridge);
    }
    // Soft shading at both ends makes the ridges read as a rolling surface.
    canvas.drawRect(
      wheel,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xE6091321),
            Color(0x00091321),
            Color(0x00091321),
            Color(0xE6091321),
          ],
          stops: [0, .18, .82, 1],
        ).createShader(wheel),
    );
    canvas.restore();
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = mint.withValues(alpha: .28),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: rect.center, width: 10, height: 3),
        const Radius.circular(2),
      ),
      Paint()..color = mint.withValues(alpha: .85),
    );
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => oldDelegate.offset != offset;
}
