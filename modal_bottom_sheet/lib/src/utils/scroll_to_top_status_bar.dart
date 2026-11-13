import 'package:flutter/material.dart';

typedef StatusBarGestureDetectorCallback = void Function(BuildContext context);

/// Widget that that will make the [scrollController] to scroll the top
/// when tapped on the status bar
///
/// Extracted from [Scaffold] and used in [Sheet]
class StatusBarGestureDetector extends StatefulWidget {
  const StatusBarGestureDetector({
    super.key,
    required this.child,
    required this.onTap,
  });

  final Widget child;

  final StatusBarGestureDetectorCallback onTap;

  @override
  State<StatusBarGestureDetector> createState() =>
      _StatusBarGestureDetectorState();
}

class _StatusBarGestureDetectorState extends State<StatusBarGestureDetector> {
  final OverlayPortalController controller = OverlayPortalController();

  /// The route that holds this sheet. [_updateOverlay] reads its state, and
  /// the animation status listener is removed from it on change or dispose.
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A change of route.offstage does not trigger didChangeDependencies. The
    // status listener sees it instead: ModalRoute.animation is a proxy that
    // switches to an always completed animation while the route is offstage,
    // so its status changes whenever offstage does.
    final route = ModalRoute.of(context);
    if (route != _route) {
      _removeRouteStatusListener();
      _route = route;
      _addRouteStatusListener();
      // OverlayPortalController.show/hide must not run during build.
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateOverlay());
    }
  }

  @override
  void dispose() {
    _removeRouteStatusListener();
    super.dispose();
  }

  void _addRouteStatusListener() =>
      _route?.animation?.addStatusListener(_onRouteAnimationStatusChanged);

  void _removeRouteStatusListener() =>
      _route?.animation?.removeStatusListener(_onRouteAnimationStatusChanged);

  void _onRouteAnimationStatusChanged(AnimationStatus status) =>
      _updateOverlay();

  /// Shows the status bar tap target only while the sheet is fully open and
  /// onstage.
  ///
  /// While the route is offstage (the first frame of a push, see
  /// HeroController) or animating, the content of the sheet is not in the
  /// semantics tree, but the overlay child would be, because it lives on the
  /// root overlay. The framework then sends a semantics node whose traversal
  /// parent is missing, which on iOS can wipe the whole accessibility tree
  /// (flutter/flutter#190357, flutter/flutter#194541).
  void _updateOverlay() {
    if (!mounted) return;
    final route = _route;
    // route.animation reports completed while the route is offstage, so
    // offstage has to be checked on its own.
    final shouldShow = route == null ||
        (!route.offstage && (route.animation?.isCompleted ?? true));
    if (shouldShow == controller.isShowing) return;
    if (shouldShow) {
      controller.show();
    } else {
      controller.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = View.of(context);
    return OverlayPortal.targetsRootOverlay(
      controller: controller,
      overlayChildBuilder: (context) {
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: view.padding.top / view.devicePixelRatio,
            width: double.infinity,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onTap(context),
              // iOS accessibility automatically adds scroll-to-top to the clock in the status bar
              excludeFromSemantics: true,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
