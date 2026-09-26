/// A field the visitor writes in.
///
/// Keeps two things: the strokes, which go to the recogniser, and a rendered
/// PNG, which is the record. The web version threw the strokes away and kept
/// only the picture, which is why recognition there was so much worse.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Ink;
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';

/// What the pad produced: strokes to recognise, pixels to keep.
class Handwriting {
  const Handwriting(this.strokes, this.png);
  final List<Stroke> strokes;
  final Uint8List? png;

  bool get isEmpty => strokes.isEmpty;
}

class HandwritingPad extends StatefulWidget {
  const HandwritingPad({
    super.key,
    required this.label,
    required this.controller,
    this.aspectRatio = 3.8,
  });

  final String label;
  final HandwritingPadController controller;

  /// Sized by ratio rather than a fixed height, so the box keeps its shape at
  /// any width and looks the same when the record is read back.
  final double aspectRatio;

  @override
  State<HandwritingPad> createState() => _HandwritingPadState();
}

/// Lets the form clear every pad and collect what was written.
class HandwritingPadController extends ChangeNotifier {
  _HandwritingPadState? _state;

  Future<Handwriting> read() async =>
      _state?.capture() ?? const Handwriting([], null);

  void clear() => _state?.clearPad();

  bool get isEmpty => _state?._strokes.isEmpty ?? true;
}

class _HandwritingPadState extends State<HandwritingPad> {
  final List<Stroke> _strokes = [];
  final List<StrokePoint> _current = [];
  final List<List<Offset>> _drawn = [];
  List<Offset> _drawnCurrent = [];

  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    super.dispose();
  }

  /// A palm resting on the glass reports as touch, not stylus. Ignoring touch
  /// is the whole of palm rejection; the web version had no equivalent and a
  /// resting hand drew on it.
  bool _isPen(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  void _start(PointerDownEvent event) {
    if (!_isPen(event.kind)) return;
    _current.clear();
    _addPoint(event.localPosition);
    setState(() => _drawnCurrent = [event.localPosition]);
  }

  void _extend(PointerMoveEvent event) {
    if (!_isPen(event.kind) || _drawnCurrent.isEmpty) return;
    _addPoint(event.localPosition);
    setState(() => _drawnCurrent = [..._drawnCurrent, event.localPosition]);
  }

  void _end(PointerUpEvent event) {
    if (_current.isEmpty) return;
    _strokes.add(Stroke()..points = List.of(_current));
    _drawn.add(List.of(_drawnCurrent));
    _current.clear();
    setState(() => _drawnCurrent = []);
  }

  void _addPoint(Offset position) {
    _current.add(
      StrokePoint(
        x: position.dx,
        y: position.dy,
        // the recogniser uses timing as a signal, so real timestamps matter
        t: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void clearPad() {
    setState(() {
      _strokes.clear();
      _current.clear();
      _drawn.clear();
      _drawnCurrent = [];
    });
  }

  /// Render what was written to a PNG, white background so it reads like ink
  /// on paper wherever it is shown.
  Future<Handwriting> capture() async {
    if (_strokes.isEmpty || _size.isEmpty) {
      return Handwriting(List.of(_strokes), null);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _size.width, _size.height),
      Paint()..color = Colors.white,
    );
    _paintStrokes(canvas, _drawn, const []);
    final image = await recorder
        .endRecording()
        .toImage(_size.width.round(), _size.height.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    return Handwriting(List.of(_strokes), data?.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.label.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            TextButton(
              onPressed: clearPad,
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 44), // a real touch target
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Clear'),
            ),
          ],
        ),
        AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _size = Size(constraints.maxWidth, constraints.maxHeight);
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                // Without this the enclosing scroll view treats a pen stroke
                // as a drag and scrolls the page out from under the writer.
                // An eager recogniser restricted to the stylus claims the
                // gesture the moment the pen lands, so the Scrollable loses -
                // while a finger still scrolls normally over the pad.
                child: RawGestureDetector(
                  gestures: <Type, GestureRecognizerFactory>{
                    EagerGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            EagerGestureRecognizer>(
                      () => EagerGestureRecognizer(
                        supportedDevices: const {
                          PointerDeviceKind.stylus,
                          PointerDeviceKind.invertedStylus,
                        },
                      ),
                      (_) {},
                    ),
                  },
                  child: Listener(
                    onPointerDown: _start,
                    onPointerMove: _extend,
                    onPointerUp: _end,
                    child: CustomPaint(
                      painter: _PadPainter(_drawn, _drawnCurrent),
                      size: Size.infinite,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

void _paintStrokes(
  Canvas canvas,
  List<List<Offset>> strokes,
  List<Offset> current,
) {
  final paint = Paint()
    ..color = const Color(0xFF111111)
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;

  for (final stroke in [...strokes, current]) {
    if (stroke.length < 2) continue;
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (final point in stroke.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }
}

class _PadPainter extends CustomPainter {
  _PadPainter(this.strokes, this.current);

  final List<List<Offset>> strokes;
  final List<Offset> current;

  @override
  void paint(Canvas canvas, Size size) =>
      _paintStrokes(canvas, strokes, current);

  @override
  bool shouldRepaint(covariant _PadPainter old) => true;
}
