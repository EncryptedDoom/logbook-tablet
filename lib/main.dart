/// Digital Logbook - the tablet app.
///
/// Everything runs on the device: SQLite for the records, ML Kit for
/// recognition. No server, and no network once the recognition model has been
/// fetched the first time.
library;

import 'package:flutter/material.dart';

import 'database.dart';
import 'entry_screen.dart';
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
      home: const CoverScreen(),
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

  @override
  Widget build(BuildContext context) {
    final ready = _db != null;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '7th Battalion',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      letterSpacing: 4,
                      color: const Color(0xFFD9B46A),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'VISITORS BOOK',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(letterSpacing: 8),
              ),
              const SizedBox(height: 24),
              Container(width: 160, height: 1, color: const Color(0xFF8A6B35)),
              const SizedBox(height: 24),
              Text(
                'Please record your visit. Every entry is written by hand.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              FilledButton(
                style:
                    FilledButton.styleFrom(minimumSize: const Size(280, 56)),
                onPressed: ready
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EntryScreen(
                              db: _db!,
                              recogniser: _recogniser,
                            ),
                          ),
                        )
                    : null,
                child: Text(ready ? 'PROCEED' : 'Preparing...'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 24),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
