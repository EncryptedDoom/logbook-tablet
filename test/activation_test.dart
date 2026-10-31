import 'package:flutter_test/flutter_test.dart';
import 'package:logbook/activation_codec.dart';

void main() {
  // a throwaway key, not the real one
  final seed = List<int>.generate(32, (i) => i * 7 % 256);

  test('a code signed for a tablet unlocks that tablet', () async {
    final device = await deviceCodeFor('a1b2c3d4e5f60718');
    final key = await publicKeyFor(seed);
    final code = await signActivation(device, seed);
    expect(await verifyActivation(device, code, key), isTrue);
  });

  test('the same code fails on any other tablet', () async {
    final mine = await deviceCodeFor('a1b2c3d4e5f60718');
    final theirs = await deviceCodeFor('ffffffffffffffff');
    final code = await signActivation(mine, seed);
    expect(await verifyActivation(theirs, code, await publicKeyFor(seed)), isFalse);
  });

  test('a code from a different key is rejected', () async {
    final device = await deviceCodeFor('a1b2c3d4e5f60718');
    final otherSeed = List<int>.filled(32, 1);
    final code = await signActivation(device, otherSeed);
    expect(await verifyActivation(device, code, await publicKeyFor(seed)), isFalse);
  });

  test('one changed character is rejected', () async {
    final device = await deviceCodeFor('a1b2c3d4e5f60718');
    final code = await signActivation(device, seed);
    final tampered = (code[10] == 'A' ? 'B' : 'A');
    final altered = code.replaceRange(10, 11, tampered);
    expect(await verifyActivation(device, altered, await publicKeyFor(seed)), isFalse);
  });

  test('typing is forgiven: case, dashes, spaces, O for 0', () async {
    final device = await deviceCodeFor('a1b2c3d4e5f60718');
    final code = await signActivation(device, seed);
    final typed = formatActivationCode(code).toLowerCase().replaceAll('0', 'o');
    expect(await verifyActivation(device, ' $typed ', await publicKeyFor(seed)), isTrue);
  });

  test('garbage is rejected, not thrown', () async {
    final device = await deviceCodeFor('a1b2c3d4e5f60718');
    final key = await publicKeyFor(seed);
    expect(await verifyActivation(device, '', key), isFalse);
    expect(await verifyActivation(device, 'https://example.com', key), isFalse);
  });

  test('device codes are 12 characters and stable', () async {
    final a = await deviceCodeFor('a1b2c3d4e5f60718');
    expect(a.length, 12);
    expect(isDeviceCode(formatDeviceCode(a)), isTrue);
    expect(await deviceCodeFor('a1b2c3d4e5f60718'), a);
  });
}
