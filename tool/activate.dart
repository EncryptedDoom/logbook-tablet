/// Approves a tablet to run the Visitors Book. Runs on the administrator's PC,
/// fully offline.
///
///   dart run tool/activate.dart init
///       Once, ever: makes the private key and writes its public half into
///       lib/activation_key.dart. Rebuild the app after this.
///
///   dart run tool/activate.dart 7KQ4-M2XD-9PRA
///       Makes the activation code for the tablet showing that device code,
///       and opens it as a QR code to scan.
///
/// The private key lives outside the project, in %USERPROFILE%\.logbook, so it
/// can never be committed or shipped inside the app. Back it up: without it no
/// new tablet can be activated, short of a new key and a new build.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:logbook/activation_codec.dart';
import 'package:qr/qr.dart';

final _home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']!;
final _keyDir = Directory('$_home${Platform.pathSeparator}.logbook');
final _keyFile = File('${_keyDir.path}${Platform.pathSeparator}activation-private-key.txt');
final _outDir = Directory('${_keyDir.path}${Platform.pathSeparator}activations');
const _publicKeyFile = 'lib/activation_key.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    _fail('Usage:\n'
        '  dart run tool/activate.dart init\n'
        '  dart run tool/activate.dart <DEVICE-CODE>');
  }
  if (args.single == 'init') return _init();
  return _activate(args.single);
}

Future<void> _init() async {
  // Never overwrite: a new key would lock out every tablet already activated.
  if (await _keyFile.exists()) {
    _fail('A private key already exists at ${_keyFile.path}\n'
        'Delete it yourself first if you really mean to replace it - every '
        'activated tablet would then need activating again.');
  }
  final random = Random.secure();
  final seed = List<int>.generate(32, (_) => random.nextInt(256));
  await _keyDir.create(recursive: true);
  await _keyFile.writeAsString(base64.encode(seed), flush: true);
  await _writePublicKey(await publicKeyFor(seed));

  stdout.writeln('Private key saved to ${_keyFile.path}');
  stdout.writeln('Public key written to $_publicKeyFile - rebuild the app.');
  stdout.writeln('Back up the private key somewhere safe and offline. '
      'Never share it, and never put it in the project folder.');
}

Future<void> _writePublicKey(List<int> key) async {
  final bytes = [
    for (var i = 0; i < key.length; i += 8)
      '  ${key.sublist(i, min(i + 8, key.length)).join(', ')},',
  ].join('\n');
  await File(_publicKeyFile).writeAsString('''
/// The public half of the activation key, written by
/// `dart run tool/activate.dart init`. It can check an activation code but
/// cannot make one, so it is safe to ship inside the app.
library;

const activationPublicKey = <int>[
$bytes
];
''');
}

Future<void> _activate(String deviceCode) async {
  if (!isDeviceCode(deviceCode)) {
    _fail('"$deviceCode" is not a device code. It should be 12 letters and '
        'digits, like 7KQ4-M2XD-9PRA, exactly as the tablet shows it.');
  }
  if (!await _keyFile.exists()) {
    _fail('No private key at ${_keyFile.path}\n'
        'Run "dart run tool/activate.dart init" first (once only).');
  }
  final seed = base64.decode((await _keyFile.readAsString()).trim());

  // Catch the one mistake that would waste a trip to the tablet: a build
  // made with a different key would reject every code signed here.
  final expected = await publicKeyFor(seed);
  final source = await File(_publicKeyFile).readAsString();
  if (!source.contains(expected.take(8).join(', '))) {
    stderr.writeln('Warning: $_publicKeyFile does not match this private key. '
        'Tablets running a build of the current source will reject this code.');
  }

  final code = await signActivation(deviceCode, seed);
  final pretty = formatDeviceCode(deviceCode);
  await _outDir.create(recursive: true);
  final page = File(
    '${_outDir.path}${Platform.pathSeparator}activation-$pretty.html',
  );
  await page.writeAsString(_html(pretty, code));

  stdout.writeln('Device code:     $pretty');
  stdout.writeln('Activation code: ${formatActivationCode(code)}');
  stdout.writeln('QR code saved to ${page.path}');
  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', page.path]);
  }
}

/// A page with the QR, big enough to scan off the monitor, a photo of it, or
/// a printout - plus the code as text in case the camera is not working.
String _html(String deviceCode, String code) {
  final qr = QrImage(
    QrCode.fromData(data: code, errorCorrectLevel: QrErrorCorrectLevel.M),
  );
  final n = qr.moduleCount;
  final squares = StringBuffer();
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (qr.isDark(r, c)) squares.write('M${c + 4} ${r + 4}h1v1h-1z');
    }
  }
  // 4 modules of white all round: scanners need the quiet zone
  final size = n + 8;
  return '''<!doctype html>
<html><head><meta charset="utf-8"><title>Activation $deviceCode</title>
<style>
  body { font-family: system-ui, sans-serif; text-align: center; margin: 40px; background: #fff; color: #111; }
  svg { width: 360px; height: 360px; }
  .code { font-family: Consolas, monospace; font-size: 18px; max-width: 520px; margin: 0 auto; }
</style></head><body>
<h1>Visitors Book activation</h1>
<p>For the tablet showing device code <strong class="code">$deviceCode</strong></p>
<svg viewBox="0 0 $size $size" shape-rendering="crispEdges">
  <rect width="$size" height="$size" fill="#fff"/>
  <path d="$squares" fill="#000"/>
</svg>
<p>On the tablet, press <strong>Scan activation code</strong> and point it at this QR code.</p>
<p>If the camera is not working, choose <em>Type the code instead</em> and enter:</p>
<p class="code">${formatActivationCode(code)}</p>
<p style="color:#666">This code works only on that one tablet.</p>
</body></html>
''';
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}
