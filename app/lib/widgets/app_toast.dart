import 'dart:async';

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The design's floating confirmation toast.
///
/// It listens to [AppState] directly rather than relying on a parent rebuild so
/// it can own its own dismissal timer.
class AppToast extends StatefulWidget {
  const AppToast({super.key, required this.state});

  final AppState state;

  static const _visibleFor = Duration(milliseconds: 2600);

  @override
  State<AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<AppToast> {
  Timer? _timer;
  String? _message;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    final next = widget.state.toast;
    if (next == null || next == _message) return;

    setState(() => _message = next);
    // A new message restarts the clock rather than inheriting the old one's.
    _timer?.cancel();
    _timer = Timer(AppToast._visibleFor, () {
      if (!mounted) return;
      setState(() => _message = null);
      widget.state.clearToast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = _message;

    return IgnorePointer(
      child: AnimatedSlide(
        offset: message == null ? const Offset(0, 0.4) : Offset.zero,
        duration: DsMotion.base,
        curve: DsMotion.easeOut,
        child: AnimatedOpacity(
          opacity: message == null ? 0 : 1,
          duration: DsMotion.base,
          curve: DsMotion.easeOut,
          child: message == null
              ? const SizedBox.shrink()
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DsSpace.s4,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: DsColors.surfaceInverse,
                    borderRadius: BorderRadius.circular(DsRadius.md),
                    boxShadow: DsShadows.lg,
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: DsText.body(
                      size: 13,
                      weight: DsWeight.bold,
                      height: 1.3,
                      color: Colors.white,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
