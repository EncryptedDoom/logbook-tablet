/// The codes behind device activation, shared by the app and the PC tool
/// (tool/activate.dart), so both sides agree on every byte.
///
/// The tablet shows a short device code. Whoever holds the private key signs
/// it on their PC; the signature is the activation code, handed back as a QR.
/// The app carries only the public key, so it can check a code but can never
/// make one - and a code signed for one tablet fails on every other.
///
/// Pure Dart, no Flutter, so the PC tool can import it.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Crockford's base32: digits and capitals, minus I, L, O and U, so nothing
/// read off a screen can be mistaken for something else.
const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// 12 characters, 60 bits: short enough to read out over a phone, far too
/// many for two tablets to collide.
const _deviceCodeLength = 12;

/// An Ed25519 signature, always.
const _signatureLength = 64;

String base32Encode(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(_alphabet[(buffer >> bits) & 31]);
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

/// Null if [text] holds anything that is not base32. Leftover bits at the end
/// are dropped, the reverse of the padding [base32Encode] adds.
List<int>? base32Decode(String text) {
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final char in normalise(text).split('')) {
    final value = _alphabet.indexOf(char);
    if (value < 0) return null;
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buffer >> bits) & 255);
    }
    buffer &= (1 << bits) - 1;
  }
  return out;
}

/// Forgive how a person types a code: case, spaces and dashes don't matter,
/// and the letters Crockford leaves out are read as the digits they look like.
String normalise(String text) => text
    .toUpperCase()
    .replaceAll(RegExp(r'[\s-]'), '')
    .replaceAll('O', '0')
    .replaceAll('I', '1')
    .replaceAll('L', '1');

/// The code this tablet shows, derived from Android's per-device ID. Hashed
/// rather than shown raw, so the code says nothing about the device.
Future<String> deviceCodeFor(String androidId) async {
  final hash = await Sha256().hash(utf8.encode('logbook-device-v1:$androidId'));
  return base32Encode(hash.bytes.sublist(0, 8)).substring(0, _deviceCodeLength);
}

/// Groups of four, for reading aloud: 7KQ4-M2XD-9PRA.
String formatDeviceCode(String code) => _group(normalise(code), 4);

/// Groups of five, for the rare case it has to be typed.
String formatActivationCode(String code) => _group(normalise(code), 5);

String _group(String text, int size) => [
      for (var i = 0; i < text.length; i += size)
        text.substring(i, i + size > text.length ? text.length : i + size),
    ].join('-');

bool isDeviceCode(String text) {
  final code = normalise(text);
  return code.length == _deviceCodeLength &&
      code.split('').every(_alphabet.contains);
}

/// What actually gets signed. The prefix keeps a signature made for anything
/// else from ever passing as an activation.
List<int> _message(String deviceCode) =>
    utf8.encode('logbook-activation-v1:${normalise(deviceCode)}');

/// PC side: sign [deviceCode] with the private key's 32-byte [seed].
Future<String> signActivation(String deviceCode, List<int> seed) async {
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final signature = await Ed25519().sign(_message(deviceCode), keyPair: keyPair);
  return base32Encode(signature.bytes);
}

/// The public half of a private key's [seed], to embed in the app.
Future<List<int>> publicKeyFor(List<int> seed) async {
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  return (await keyPair.extractPublicKey()).bytes;
}

/// Tablet side: does [activationCode] unlock the tablet showing [deviceCode]?
Future<bool> verifyActivation(
  String deviceCode,
  String activationCode,
  List<int> publicKey,
) async {
  final bytes = base32Decode(activationCode);
  if (bytes == null || bytes.length != _signatureLength) return false;
  return Ed25519().verify(
    _message(deviceCode),
    signature: Signature(
      bytes,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );
}
