/// A field the visitor writes in.
///
/// Keeps two things: the strokes, which go to the recogniser, and a rendered
/// PNG, which is the record. The web version threw the strokes away and kept
/// only the picture, which is why recognition there was so much worse.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Ink;
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';

import 'theme.dart';

/// Lets a finger or mouse draw, for testing in the emulator, where the mouse
/// arrives as touch. Off unless the app is built with
///   --dart-define=ALLOW_FINGER_DRAWING=true
/// Deliberately not tied to debug mode: the tablet runs debug builds too, and
/// must keep palm rejection.
const allowFingerDrawing = bool.fromEnvironment('ALLOW_FINGER_DRAWING');

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

/// Lets the form clear every pad, collect what was written, and hear when
/// ink lands (e.g. to enable a submit button).
class HandwritingPadController extends ChangeNotifier {
  _HandwritingPadState? _state;

  Future<Handwriting> read() async =>
      _state?.capture() ?? const Handwriting([], null);

  void clear() => _state?.clearPad();

  bool get isEmpty => _state?._strokes.isEmpty ?? true;

  void _notifyInkChanged() => notifyListeners();
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
  // DEBUG ONLY - lets the emulator draw with a mouse; release stays
  // stylus-only.
  bool _isPen(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus ||
      (allowFingerDrawing &&
          (kind == PointerDeviceKind.touch ||
              kind == PointerDeviceKind.mouse)) ||
      (kDebugMode &&
          (kind == PointerDeviceKind.touch || kind == PointerDeviceKind.mouse));

  /// True from pen-down to pen-up, whether or not the pen is currently inside
  /// the box - so a stroke that wanders out and comes back can resume.
  bool _penDown = false;

  Rect get _bounds => Offset.zero & _size;

  /// Pull a point onto the box edge, so a stroke that leaves ends at the
  /// border instead of stopping short of it.
  Offset _clamp(Offset p) => Offset(
        p.dx.clamp(0.0, _size.width),
        p.dy.clamp(0.0, _size.height),
      );

  void _start(PointerDownEvent event) {
    if (!_isPen(event.kind)) return;
    _penDown = true;
    _beginStroke(event.localPosition);
  }

  /// Once the pen lands in this box, Flutter keeps routing its moves here even
  /// after it leaves - which is how lines used to run off the edge. So: end
  /// the stroke at the border when the pen crosses it, ignore it while it is
  /// outside, and start a fresh stroke if it comes back in without lifting.
  void _extend(PointerMoveEvent event) {
    if (!_isPen(event.kind) || !_penDown) return;
    final point = event.localPosition;
    final inside = _bounds.contains(point);
    final drawing = _drawnCurrent.isNotEmpty;

    if (drawing && inside) {
      _addPoint(point);
      setState(() => _drawnCurrent = [..._drawnCurrent, point]);
    } else if (drawing && !inside) {
      final edge = _clamp(point);
      _addPoint(edge);
      _drawnCurrent = [..._drawnCurrent, edge];
      _commitStroke();
    } else if (!drawing && inside) {
      _beginStroke(point);
    }
    // not drawing and still outside: nothing to do
  }

  void _end(PointerEvent event) {
    _penDown = false;
    _commitStroke();
  }

  void _beginStroke(Offset point) {
    _current.clear();
    _addPoint(point);
    setState(() => _drawnCurrent = [point]);
  }

  void _commitStroke() {
    if (_current.isEmpty) return;
    _strokes.add(Stroke()..points = List.of(_current));
    _drawn.add(List.of(_drawnCurrent));
    _current.clear();
    setState(() => _drawnCurrent = []);
    // lets the form know ink has landed, e.g. to enable Record Entry
    widget.controller._notifyInkChanged();
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
    widget.controller._notifyInkChanged();
  }

  /// Render what was written to a PNG, paper background so it reads like ink
  /// on paper wherever it is shown.
  Future<Handwriting> capture() async {
    if (_strokes.isEmpty || _size.isEmpty) {
      return Handwriting(List.of(_strokes), null);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _size.width, _size.height),
      Paint()..color = AppColors.paper,
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
            Text(widget.label.toUpperCase(), style: labelStyle(context)),
            IconButton(
              onPressed: clearPad,
              tooltip: 'Clear',
              icon: const Icon(Icons.backspace_outlined, size: 20),
              iconSize: 20,
              color: AppColors.textMuted,
              constraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48, // a real touch target
              ),
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
                  color: AppColors.paper,
                  border: Border.all(color: AppColors.ink.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(AppRadii.pad),
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
                        supportedDevices: {
                          PointerDeviceKind.stylus,
                          PointerDeviceKind.invertedStylus,
                          if (allowFingerDrawing) ...[
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                          ],
                          // DEBUG ONLY - lets the emulator draw with a
                          // mouse; release stays stylus-only.
                          if (kDebugMode) ...[
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                          ],
                        },
                      ),
                      (_) {},
                    ),
                  },
                  child: Listener(
                    onPointerDown: _start,
                    onPointerMove: _extend,
                    onPointerUp: _end,
                    // e.g. the system takes the pointer for a gesture
                    onPointerCancel: _end,
                    // belt and braces: nothing this pad paints can show
                    // outside it, whatever the stroke data holds
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.pad),
                      child: CustomPaint(
                        painter: _PadPainter(_drawn, _drawnCurrent),
                        size: Size.infinite,
                      ),
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
    ..color = AppColors.ink
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
  void paint(Canvas canvas, Size size) {
    // a faint baseline near the lower third, like a ruled page - guidance
    // only, never part of the recorded ink
    final y = size.height * 2 / 3;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = AppColors.ink.withValues(alpha: 0.12)
        ..strokeWidth = 1,
    );
    _paintStrokes(canvas, strokes, current);
  }

  @override
  bool shouldRepaint(covariant _PadPainter old) => true;
}
