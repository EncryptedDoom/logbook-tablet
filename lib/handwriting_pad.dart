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

import 'box_style.dart';

/// Lets a finger or mouse draw, for testing in the emulator, where the mouse
/// arrives as touch. Off unless the app is built with
///   --dart-define=ALLOW_FINGER_DRAWING=true
/// Deliberately not tied to debug mode: the tablet runs debug builds too, and
/// must keep palm rejection.
const allowFingerDrawing = bool.fromEnvironment('ALLOW_FINGER_DRAWING');

/// Pixels saved per logical pixel of the box, best first. Three gives print
/// quality; the next is the fallback for writing so dense that the PNG passes
/// [_maxPngBytes].
const _captureScales = [3.0, 2.0];

/// Every field of a record is read back as one database row, and Android
/// cannot read a row over 2 MB. Keeping the largest box under this leaves room
/// for the smaller ones.
const _maxPngBytes = 800 * 1024;

/// Finds the handle in tests.
const padResizeHandleKey = ValueKey('pad-resize-handle');

/// How far the handle reaches onto the bottom of the box, and below it.
/// Together a comfortable touch target, and room for its one line of help.
const _handleOnBox = 24.0;
const _handleBelowBox = 24.0;

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
    this.maxGrowth = 1,
  });

  final String label;
  final HandwritingPadController controller;

  /// Sized by ratio rather than a fixed height, so the box keeps its shape at
  /// any width and looks the same when the record is read back.
  final double aspectRatio;

  /// How many times its starting height the box can be dragged out to, by the
  /// handle under it. 1 means it stays the size it is, with no handle.
  final double maxGrowth;

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

  /// Current height as a multiple of the starting height.
  double _growth = 1;

  /// True while the handle is being pushed up against what is written.
  bool _inkInTheWay = false;

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
      kind == PointerDeviceKind.invertedStylus ||
      (allowFingerDrawing &&
          (kind == PointerDeviceKind.touch || kind == PointerDeviceKind.mouse));

  /// True from pen-down to pen-up, whether or not the pen is currently inside
  /// the box - so a stroke that wanders out and comes back can resume.
  bool _penDown = false;

  Rect get _bounds => Offset.zero & _size;

  /// Pull a point onto the box edge, so a stroke that leaves ends at the
  /// border instead of stopping short of it.
  Offset _clamp(Offset p) =>
      Offset(p.dx.clamp(0.0, _size.width), p.dy.clamp(0.0, _size.height));

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
  }

  /// Follow the handle, between the starting height and the limit. It cannot
  /// be pushed up past the writing, which would cut off what is already there.
  void _resize(DragUpdateDetails details) {
    // from the width, not the height: several drag events can arrive before
    // the next layout, and the height would be out of date for all but the first
    final startHeight = _size.width / widget.aspectRatio;
    if (startHeight <= 0) return;
    var lowestInk = 0.0;
    for (final stroke in _drawn) {
      for (final point in stroke) {
        if (point.dy > lowestInk) lowestInk = point.dy;
      }
    }
    // a little clear of the ink, so the box edge does not sit on the line
    final smallest = ((lowestInk + 8) / startHeight).clamp(
      1.0,
      widget.maxGrowth,
    );
    final wanted = _growth + details.delta.dy / startHeight;
    setState(() {
      _inkInTheWay = wanted < smallest && smallest > 1;
      _growth = wanted.clamp(smallest, widget.maxGrowth);
    });
  }

  void _endResize() {
    if (_inkInTheWay) setState(() => _inkInTheWay = false);
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
      _growth = 1;
    });
  }

  /// Render what was written to a PNG, white background so it reads like ink
  /// on paper wherever it is shown. White rather than the pad's off-white:
  /// the PNG is the record and gets printed, and the record view tints it to
  /// match its box on screen.
  Future<Handwriting> capture() async {
    if (_strokes.isEmpty || _size.isEmpty) {
      return Handwriting(List.of(_strokes), null);
    }

    Uint8List? png;
    for (final scale in _captureScales) {
      png = await _render(scale);
      if (png == null || png.length <= _maxPngBytes) break;
    }
    return Handwriting(List.of(_strokes), png);
  }

  Future<Uint8List?> _render(double scale) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _size.width, _size.height),
      Paint()..color = Colors.white,
    );
    _paintStrokes(canvas, _drawn, const []);
    final image = await recorder.endRecording().toImage(
      (_size.width * scale).round(),
      (_size.height * scale).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
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
        _withResizeHandle(
          AspectRatio(
            aspectRatio: widget.aspectRatio / _growth,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _size = Size(constraints.maxWidth, constraints.maxHeight);
                return DecoratedBox(
                  decoration: boxDecoration,
                  // Without this the enclosing scroll view treats a pen stroke
                  // as a drag and scrolls the page out from under the writer.
                  // An eager recogniser restricted to the stylus claims the
                  // gesture the moment the pen lands, so the Scrollable loses -
                  // while a finger still scrolls normally over the pad.
                  child: RawGestureDetector(
                    gestures: <Type, GestureRecognizerFactory>{
                      EagerGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            EagerGestureRecognizer
                          >(
                            () => EagerGestureRecognizer(
                              supportedDevices: {
                                PointerDeviceKind.stylus,
                                PointerDeviceKind.invertedStylus,
                                if (allowFingerDrawing) ...[
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
                      // outside it, rounded corners included, whatever the
                      // stroke data holds
                      child: ClipRRect(
                        borderRadius: boxRadius,
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
        ),
      ],
    );
  }

  /// A strip across the box's bottom edge, partly on the box and partly under
  /// it, so that grabbing the edge itself resizes the box rather than drawing a
  /// line. Any finger or pen can drag it; being the inner gesture, it wins over
  /// the page scrolling.
  Widget _withResizeHandle(Widget box) {
    if (widget.maxGrowth <= 1) return box;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: _handleBelowBox),
          child: box,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _handleOnBox + _handleBelowBox,
          child: Semantics(
            label: 'Drag to resize ${widget.label} box',
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                key: padResizeHandleKey,
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onVerticalDragUpdate: _resize,
                onVerticalDragEnd: (_) => _endResize(),
                onVerticalDragCancel: _endResize,
                child: Column(
                  children: [
                    const SizedBox(height: _handleOnBox - 12),
                    Container(
                      width: 96,
                      height: 6,
                      decoration: BoxDecoration(
                        color: boxHint,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Spacer(),
                    if (_inkInTheWay)
                      Text(
                        'Writing is in the way. Clear it to shrink the box.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
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
