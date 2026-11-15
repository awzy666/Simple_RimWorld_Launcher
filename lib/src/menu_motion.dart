import 'package:fluent_ui/fluent_ui.dart';

/// First grows to cover the destination, then retracts the trailing edge.
/// Retargeting starts from the currently painted rectangle.
class StretchMenuIndicator extends StatefulWidget {
  const StretchMenuIndicator({
    super.key,
    required this.target,
    required this.color,
    required this.markerKey,
  });

  final Rect target;
  final Color color;
  final Key markerKey;

  @override
  State<StretchMenuIndicator> createState() => _StretchMenuIndicatorState();
}

class _StretchMenuIndicatorState extends State<StretchMenuIndicator>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  late Rect start = widget.target, destination = widget.target;
  bool reduceMotion = false;

  Rect get current {
    final span = start.expandToInclude(destination);
    final time = controller.value;
    if (time <= 0.5) {
      return Rect.lerp(start, span, Curves.easeOutCubic.transform(time * 2))!;
    }
    return Rect.lerp(
      span,
      destination,
      Curves.easeInOutCubic.transform((time - 0.5) * 2),
    )!;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      controller.stop();
      start = destination = widget.target;
      controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant StretchMenuIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target == widget.target) return;
    start = current;
    destination = widget.target;
    if (reduceMotion) {
      start = destination;
      controller.value = 1;
    } else {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) =>
        Positioned.fromRect(rect: current, child: child!),
    child: IgnorePointer(
      child: ColoredBox(key: widget.markerKey, color: widget.color),
    ),
  );
}
