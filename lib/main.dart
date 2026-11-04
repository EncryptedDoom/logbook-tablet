/// Digital Logbook - the tablet app.
///
/// Everything runs on the device: SQLite for the records, ML Kit for
/// recognition. No server, and no network once the recognition model has been
/// fetched the first time.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'activation_screen.dart';
import 'database.dart';
import 'entry_screen.dart';
import 'handwriting_pad.dart' show allowFingerDrawing;
import 'licence.dart';
import 'recogniser.dart';

void main() => runApp(const LogbookApp());

class LogbookApp extends StatelessWidget {
  const LogbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visitors Book',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB08542),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF17151A),
        useMaterial3: true,
      ),
      home: const ActivationGate(),
      // a build that lets fingers draw must never pass for the real thing
      builder: allowFingerDrawing
          ? (context, child) => Banner(
              message: 'TEST MODE',
              location: BannerLocation.topEnd,
              color: Colors.red.shade700,
              child: child!,
            )
          : null,
    );
  }
}

/// Nothing of the book - not even the cover - opens on a tablet that has not
/// been activated.
class ActivationGate extends StatefulWidget {
  const ActivationGate({super.key});

  @override
  State<ActivationGate> createState() => _ActivationGateState();
}

class _ActivationGateState extends State<ActivationGate> {
  // Every build checks, debug included: the tablet itself runs debug builds,
  // and a bypass there would let any copied APK run unactivated.
  late Future<bool> _activated = Licence.isActivated();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _activated,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold();
        }
        if (snapshot.data == true) return const CoverScreen();
        return ActivationScreen(
          // block body: an arrow here would hand the Future to setState,
          // which throws and leaves the screen stuck on its spinner
          onActivated: () => setState(() {
            _activated = Future.value(true);
          }),
        );
      },
    );
  }
}

class CoverScreen extends StatefulWidget {
  const CoverScreen({super.key});

  @override
  State<CoverScreen> createState() => _CoverScreenState();
}

class _CoverScreenState extends State<CoverScreen> {
  final _recogniser = Recogniser();
  LogbookDatabase? _db;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
    // the cover is a kiosk-style splash - no status bar while it's up
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _recogniser.dispose();
    super.dispose();
  }

  /// Open the database and fetch the recognition model before a visitor is
  /// standing at the screen, so neither cost lands mid-entry.
  Future<void> _open() async {
    try {
      final db = await LogbookDatabase.open();
      final modelError = await _recogniser.prepare();
      if (!mounted) return;
      setState(() {
        _db = db;
        // the book still works without recognition; only search suffers
        _error = modelError;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the logbook: $e');
    }
  }

  Future<void> _proceed() async {
    // the entry screen is a normal working screen, not a kiosk splash
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntryScreen(db: _db!, recogniser: _recogniser),
      ),
    );
    // back on the cover: hide the system bars again
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// The cover picture's shape, and where the button sits on it, as fractions
  /// of its width and height: centred under the WELCOMES badge, in the cream
  /// gap between that badge (ends at 70%) and the red banner (starts at 87%).
  /// Measured on the image itself, so the button stays put on any screen.
  static const _coverAspect = 2624 / 1632;
  static const _buttonAt = Offset(0.694, 0.81);
  static const _coverCream = Color(0xFFFFFFCC);

  @override
  Widget build(BuildContext context) {
    final ready = _db != null;
    return Scaffold(
      // On screens wider than the picture, the bands either side continue its
      // own edges: white down its left side, cream down its right.
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.white, _coverCream, _coverCream],
            stops: [0, 0.5, 0.5, 1],
          ),
        ),
        child: Center(
          child: AspectRatio(
            aspectRatio: _coverAspect,
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/cover.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                  Positioned(
                    left: box.maxWidth * _buttonAt.dx,
                    top: box.maxHeight * _buttonAt.dy,
                    child: FractionalTranslation(
                      // centre the button on that point, not its corner
                      translation: const Offset(-0.5, -0.5),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(280, 64),
                              backgroundColor: const Color(0xFF6F4E37),
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(
                                fontFamily: 'serif',
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            onPressed: ready ? _proceed : null,
                            child: Text(ready ? 'PROCEED' : 'Preparing...'),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: const TextStyle(color: Color(0xFFB00020)),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
