/// What an unapproved tablet shows instead of the book: its device code, and
/// a way to take in the activation code - scanned as a QR, or typed if the
/// camera is not available.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'activation_codec.dart';
import 'box_style.dart';
import 'licence.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key, required this.onActivated});

  final VoidCallback onActivated;

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _typed = TextEditingController();
  String? _deviceCode;
  String? _error;
  bool _checking = false;
  bool _showTyping = false;

  @override
  void initState() {
    super.initState();
    Licence.deviceCode().then(
      (code) => mounted ? setState(() => _deviceCode = code) : null,
      onError: (Object e) => mounted
          ? setState(() => _error = 'Could not read this tablet: $e')
          : null,
    );
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final scanned = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _ScannerScreen()));
    if (scanned != null) await _submit(scanned);
  }

  Future<void> _submit(String code) async {
    // the easy mistake: typing back the code this screen is showing
    if (_deviceCode != null && normalise(code) == normalise(_deviceCode!)) {
      setState(
        () => _error =
            'That is this tablet\'s own device code. Enter the '
            'longer activation code the administrator made from it.',
      );
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await Licence.activate(code);
    if (!mounted) return;
    if (ok) {
      widget.onActivated();
    } else {
      setState(() {
        _checking = false;
        _error =
            'That activation code is not for this tablet. '
            'Check it was made for the code shown above.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _deviceCode;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'This tablet is not activated',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Send this device code to the administrator. They will give '
                  'you an activation QR code to scan.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Text('DEVICE CODE', style: theme.textTheme.labelMedium),
                const SizedBox(height: 8),
                SelectableText(
                  code == null ? '...' : formatDeviceCode(code),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 4,
                    color: const Color(0xFFD9B46A),
                  ),
                ),
                const SizedBox(height: 40),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(320, 56),
                  ),
                  onPressed: code == null || _checking ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('SCAN ACTIVATION CODE'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _showTyping = !_showTyping),
                  child: Text(_showTyping ? 'Hide' : 'Type the code instead'),
                ),
                if (_showTyping) ...[
                  const SizedBox(height: 8),
                  BoxLabel(
                    'Activation code (about 100 characters)',
                    child: TextField(
                      controller: _typed,
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9A-Za-z\s-]'),
                        ),
                      ],
                      style: boxText,
                      cursorColor: boxInk,
                      decoration: boxInput(
                        context,
                        hint: 'XXXXX-XXXXX-XXXXX-...',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: code == null || _checking
                        ? null
                        : () => _submit(_typed.text),
                    child: const Text('ACTIVATE'),
                  ),
                ],
                if (_checking) ...[
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen camera that closes on the first QR it reads.
class _ScannerScreen extends StatefulWidget {
  const _ScannerScreen();

  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _detected(BarcodeCapture capture) {
    if (_done) return; // the camera keeps reporting the same code
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan activation code')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _detected,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'The camera is not available (${error.errorCode.name}).\n'
                  'Go back and type the code instead.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Point the camera at the activation QR code',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
