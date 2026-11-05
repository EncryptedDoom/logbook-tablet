import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/handwriting_pad.dart';

/// Pumps a single pad and returns its controller and on-screen rect.
Future<(HandwritingPadController, Rect)> _pad(WidgetTester tester) async {
  final controller = HandwritingPadController();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 380,
            child: HandwritingPad(
              label: 'name',
              controller: controller,
              aspectRatio: 3.8,
            ),
          ),
        ),
      ),
    ),
  );
  final area = find.descendant(
    of: find.byType(HandwritingPad),
    matching: find.byType(ClipRRect),
  );
  return (controller, tester.getRect(area));
}

/// Draws one stroke across the pad at [dy] below its top.
Future<void> _writeAt(WidgetTester tester, Rect box, double dy) async {
  final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
  await pen.down(box.topLeft + Offset(10, dy));
  await pen.moveTo(box.topLeft + Offset(60, dy));
  await pen.up();
  await tester.pump();
}

Future<Rect> _growingPad(
  WidgetTester tester,
  HandwritingPadController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 460,
            child: HandwritingPad(
              label: 'comment',
              controller: controller,
              aspectRatio: 4.6, // 100 tall
              maxGrowth: 2,
            ),
          ),
        ),
      ),
    ),
  );
  return _areaOf(tester);
}

Rect _areaOf(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(HandwritingPad),
    matching: find.byType(ClipRRect),
  ),
);

Future<void> _dragHandle(WidgetTester tester, double dy) async {
  await tester.drag(find.byKey(padResizeHandleKey), Offset(0, dy));
  await tester.pump();
}

void main() {
  testWidgets('writing does not change the size of the box', (tester) async {
    final box = await _growingPad(tester, HandwritingPadController());
    await _writeAt(tester, box, 70);
    expect(_areaOf(tester).height, 100);
  });

  testWidgets('dragging the handle resizes the box, up to its limit', (
    tester,
  ) async {
    await _growingPad(tester, HandwritingPadController());

    await _dragHandle(tester, 50);
    expect(_areaOf(tester).height, moreOrLessEquals(150));

    await _dragHandle(tester, 300);
    expect(
      _areaOf(tester).height,
      moreOrLessEquals(200),
      reason: 'stops at the limit',
    );

    await _dragHandle(tester, -300);
    expect(
      _areaOf(tester).height,
      moreOrLessEquals(100),
      reason: 'stops at the starting size',
    );
  });

  testWidgets('the handle cannot cut off what is written', (tester) async {
    final box = await _growingPad(tester, HandwritingPadController());
    await _dragHandle(tester, 50);
    await _writeAt(tester, box, 120);

    await _dragHandle(tester, -300);

    expect(_areaOf(tester).height, moreOrLessEquals(128));
  });

  testWidgets('it says why when the writing stops it', (tester) async {
    final box = await _growingPad(tester, HandwritingPadController());
    await _dragHandle(tester, 50);
    await _writeAt(tester, box, 120);

    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(padResizeHandleKey)),
    );
    await finger.moveBy(const Offset(0, -100));
    await tester.pump();
    expect(find.textContaining('Writing is in the way'), findsOneWidget);

    await finger.up();
    await tester.pump();
    expect(find.textContaining('Writing is in the way'), findsNothing);
  });

  testWidgets('grabbing the bottom edge resizes rather than draws', (
    tester,
  ) async {
    final controller = HandwritingPadController();
    final box = await _growingPad(tester, controller);

    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(box.bottomCenter - const Offset(0, 5));
    await pen.moveBy(const Offset(0, 30));
    await pen.moveBy(const Offset(0, 20));
    await pen.up();
    await tester.pump();

    expect(_areaOf(tester).height, moreOrLessEquals(150));
    expect(controller.isEmpty, isTrue);
  });

  testWidgets('a pad with no room to grow has no handle', (tester) async {
    await _pad(tester);
    expect(find.byKey(padResizeHandleKey), findsNothing);
  });

  testWidgets('clearing puts the box back to its starting size', (
    tester,
  ) async {
    final controller = HandwritingPadController();
    await _growingPad(tester, controller);
    await _dragHandle(tester, 50);

    controller.clear();
    await tester.pump();

    expect(_areaOf(tester).height, 100);
  });

  testWidgets('the saved picture is three times the size of the box', (
    tester,
  ) async {
    final controller = HandwritingPadController();
    final box = await _growingPad(tester, controller);
    await _dragHandle(tester, 50); // now 150 tall
    await _writeAt(tester, box, 90);

    final written = (await tester.runAsync(controller.read))!;
    final header = ByteData.sublistView(written.png!);
    expect(header.getUint32(16), 460 * 3);
    expect(header.getUint32(20), 150 * 3);
  });

  testWidgets('a stroke that leaves the box stops at its edge', (tester) async {
    final (controller, box) = await _pad(tester);

    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(box.center);
    await pen.moveTo(box.centerRight - const Offset(20, 0));
    await pen.moveTo(box.centerRight + const Offset(60, 0)); // leaves
    await pen.moveTo(box.centerRight + const Offset(120, 30)); // still out
    await pen.up();
    await tester.pump();

    final written = (await tester.runAsync(controller.read))!;
    expect(written.strokes, hasLength(1));

    for (final p in written.strokes.single.points) {
      expect(p.x, inInclusiveRange(0, box.width), reason: 'x went outside');
      expect(p.y, inInclusiveRange(0, box.height), reason: 'y went outside');
    }
    // and it reaches the border rather than stopping short of it
    expect(written.strokes.single.points.last.x, box.width);
  });

  testWidgets('coming back in without lifting starts a new stroke', (
    tester,
  ) async {
    final (controller, box) = await _pad(tester);

    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.down(box.center);
    await pen.moveTo(box.centerRight + const Offset(40, 0)); // out
    await pen.moveTo(box.center + const Offset(0, 10)); // back in
    await pen.moveTo(box.center + const Offset(30, 10));
    await pen.up();
    await tester.pump();

    final written = (await tester.runAsync(controller.read))!;
    // no line is drawn across the gap while the pen was outside
    expect(written.strokes, hasLength(2));
    for (final stroke in written.strokes) {
      for (final p in stroke.points) {
        expect(p.x, inInclusiveRange(0, box.width));
        expect(p.y, inInclusiveRange(0, box.height));
      }
    }
  });

  testWidgets('a finger never draws (palm rejection)', (tester) async {
    final (controller, box) = await _pad(tester);

    final finger = await tester.createGesture(kind: PointerDeviceKind.touch);
    await finger.down(box.center);
    await finger.moveTo(box.center + const Offset(40, 5));
    await finger.up();
    await tester.pump();

    final written = (await tester.runAsync(controller.read))!;
    expect(written.strokes, isEmpty);
  });
}
