import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

/// Tests for `StatusBarGestureDetector`
/// (lib/src/utils/scroll_to_top_status_bar.dart).
///
/// The detector puts its tap target on the root overlay with an
/// [OverlayPortal]. If that overlay child is in the semantics tree while the
/// sheet (its traversal parent) is not, e.g. on the first frame of a push when
/// the HeroController keeps the route offstage, the framework sends a
/// semantics node that nothing references. The iOS accessibility bridge drops
/// it, and the next update that lists it as a child makes the bridge fabricate
/// an empty root node, which can wipe the whole accessibility tree until the
/// app restarts (flutter/flutter#190357, flutter/flutter#194541).
void main() {
  _SemanticsRecordingBinding();

  setUp(_SemanticsRecorder.clear);

  group('semantics updates', () {
    final sheets = <String, Future<void> Function(BuildContext, WidgetBuilder)>{
      'showCupertinoModalBottomSheet': (context, builder) =>
          showCupertinoModalBottomSheet<void>(
              context: context, builder: builder),
      'showMaterialModalBottomSheet': (context, builder) =>
          showMaterialModalBottomSheet<void>(
              context: context, builder: builder),
      'showBarModalBottomSheet': (context, builder) =>
          showBarModalBottomSheet<void>(context: context, builder: builder),
    };

    for (final entry in sheets.entries) {
      testWidgets(
        '${entry.key} never lists a child the iOS bridge has already dropped',
        (tester) async {
          _SemanticsRecorder.recording = true;
          final contentKey = GlobalKey<_LateContentState>();
          await _pumpHome(
            tester,
            onPressed: (context) => entry.value(
              context,
              (context) => _LateContent(key: contentKey),
            ),
          );

          await tester.tap(find.text('Open'));
          await _pumpFrames(tester, const Duration(milliseconds: 800));

          // Content arriving after the sheet is open changes the children of
          // the sheet's root semantics node, so the traversal parent of the
          // overlay child is sent again.
          contentKey.currentState!.load();
          await _pumpFrames(tester, const Duration(milliseconds: 300));

          await tester.drag(find.byType(ListView), const Offset(0, -300));
          await _pumpFrames(tester, const Duration(milliseconds: 500));

          Navigator.of(contentKey.currentContext!).pop();
          await _pumpFrames(tester, const Duration(milliseconds: 800));
          _SemanticsRecorder.recording = false;

          expect(_SemanticsRecorder.updates, isNotEmpty);
          expect(_danglingChildren(_SemanticsRecorder.updates), isEmpty);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  });

  group('status bar tap', () {
    // With Duration.zero the sheet is already open when it is first built, so
    // no animation status change follows. Only the first check scheduled in
    // didChangeDependencies can then show the tap target.
    for (final duration in <Duration?>[null, Duration.zero]) {
      testWidgets(
        'scrolls the sheet back to the top once the sheet is open '
        '(${duration == null ? 'default duration' : 'Duration.zero'})',
        (tester) async {
          tester.view.devicePixelRatio = 3;
          tester.view.padding = const FakeViewPadding(top: 47 * 3);
          addTearDown(tester.view.reset);

          await _pumpHome(
            tester,
            onPressed: (context) => showCupertinoModalBottomSheet<void>(
              context: context,
              duration: duration,
              builder: (context) => Material(
                child: ListView.builder(
                  controller: ModalScrollController.of(context),
                  itemCount: 50,
                  itemBuilder: (context, i) =>
                      SizedBox(height: 60, child: Text('Item $i')),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();

          await tester.drag(find.byType(ListView), const Offset(0, -500));
          await tester.pumpAndSettle();
          final position =
              tester.state<ScrollableState>(find.byType(Scrollable)).position;
          expect(position.pixels, greaterThan(0));

          // Inside the 47pt status bar.
          await tester.tapAt(const Offset(200, 20));
          await tester.pumpAndSettle();
          expect(position.pixels, 0);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      );
    }
  });
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

Future<void> _pumpHome(
  WidgetTester tester, {
  required void Function(BuildContext context) onPressed,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => onPressed(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps frame by frame so that every intermediate semantics update is sent.
Future<void> _pumpFrames(WidgetTester tester, Duration total) async {
  const frame = Duration(milliseconds: 16);
  for (var elapsed = Duration.zero; elapsed < total; elapsed += frame) {
    await tester.pump(frame);
  }
}

/// A sheet whose scrollable content arrives later, like content loaded from an
/// API.
class _LateContent extends StatefulWidget {
  const _LateContent({super.key});

  @override
  State<_LateContent> createState() => _LateContentState();
}

class _LateContentState extends State<_LateContent> {
  bool _loaded = false;

  void load() => setState(() => _loaded = true);

  @override
  Widget build(BuildContext context) {
    return Material(
      child: SizedBox(
        height: 500,
        child: Column(
          children: [
            const SizedBox(height: 56, child: Center(child: Text('Title'))),
            Expanded(
              child: _loaded
                  ? ListView.builder(
                      controller: ModalScrollController.of(context),
                      itemCount: 30,
                      itemBuilder: (context, i) =>
                          SizedBox(height: 60, child: Text('Item $i')),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Semantics update recording
// -----------------------------------------------------------------------------

class _NodeUpdate {
  _NodeUpdate(
      this.id, this.childrenInTraversalOrder, this.childrenInHitTestOrder);

  final int id;
  final List<int> childrenInTraversalOrder;
  final List<int> childrenInHitTestOrder;
}

abstract final class _SemanticsRecorder {
  static bool recording = false;
  static final List<List<_NodeUpdate>> updates = <List<_NodeUpdate>>[];

  static void clear() {
    recording = false;
    updates.clear();
  }
}

class _SemanticsRecordingBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingSemanticsUpdateBuilder(super.createSemanticsUpdateBuilder());
}

/// Records [ui.SemanticsUpdateBuilder.updateNode] calls and forwards
/// everything to the real builder.
///
/// Uses [noSuchMethod] so the test does not depend on the exact `updateNode`
/// signature of the Flutter version.
class _RecordingSemanticsUpdateBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingSemanticsUpdateBuilder(this._builder);

  final ui.SemanticsUpdateBuilder _builder;
  final List<_NodeUpdate> _nodes = <_NodeUpdate>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #updateNode:
        final args = invocation.namedArguments;
        _nodes.add(_NodeUpdate(
          args[#id] as int,
          List<int>.of(args[#childrenInTraversalOrder] as Int32List),
          List<int>.of(args[#childrenInHitTestOrder] as Int32List),
        ));
        return Function.apply(_builder.updateNode,
            invocation.positionalArguments, invocation.namedArguments);
      case #updateCustomAction:
        return Function.apply(_builder.updateCustomAction,
            invocation.positionalArguments, invocation.namedArguments);
      case #build:
        if (_SemanticsRecorder.recording) {
          _SemanticsRecorder.updates.add(List<_NodeUpdate>.of(_nodes));
        }
        return _builder.build();
    }
    return super.noSuchMethod(invocation);
  }
}

/// Replays [updates] with the bookkeeping of the iOS AccessibilityBridge and
/// returns every child reference that the bridge would have to resolve with
/// `updates[uid]` (and so fabricate an empty root node):
///  * a child id is fine if the node is in the same update or still held by
///    the bridge;
///  * after each update the bridge keeps only the nodes reachable from the
///    root (id 0) through traversal children.
List<String> _danglingChildren(List<List<_NodeUpdate>> updates) {
  final dangling = <String>[];
  // Node id -> traversal children, for nodes the bridge still holds.
  final held = <int, List<int>>{};
  for (var i = 0; i < updates.length; i++) {
    final sent = {for (final node in updates[i]) node.id};
    for (final node in updates[i]) {
      for (final child in <int>{
        ...node.childrenInTraversalOrder,
        ...node.childrenInHitTestOrder
      }) {
        if (!sent.contains(child) && !held.containsKey(child)) {
          dangling.add('update $i: node #${node.id} lists child #$child, '
              'which is neither in this update nor held by the bridge');
        }
      }
    }
    for (final node in updates[i]) {
      held[node.id] = node.childrenInTraversalOrder;
    }
    final reachable = <int>{};
    void visit(int id) {
      if (!held.containsKey(id) || !reachable.add(id)) return;
      held[id]!.forEach(visit);
    }

    visit(0);
    held.removeWhere((id, _) => !reachable.contains(id));
  }
  return dangling;
}
