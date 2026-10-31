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
    matching: find.byType(ClipRect),
  );
  return (controller, tester.getRect(area));
}

void main() {
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

  testWidgets('coming back in without lifting starts a new stroke',
      (tester) async {
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
