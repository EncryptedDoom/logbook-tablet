/// Whether this tablet has been approved to run the book.
///
/// The activation code is kept in a small file beside the database. It is
/// worthless on any other tablet - it is a signature over this tablet's code
/// alone - so there is nothing to protect in it.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'activation_codec.dart';
import 'activation_key.dart';

class Licence {
  static const _channel = MethodChannel('logbook/device');

  static String? _deviceCode;

  /// This tablet's code, as shown on the activation screen.
  ///
  /// Android's ID is fixed for this app on this tablet: it survives
  /// reinstalling, and changes only on a factory reset or if the app is
  /// signed with a different key. Either of those means activating again.
  static Future<String> deviceCode() async {
    if (_deviceCode != null) return _deviceCode!;
    final id = await _channel.invokeMethod<String>('deviceId');
    if (id == null || id.isEmpty) {
      throw StateError('The tablet did not report a device ID');
    }
    return _deviceCode = await deviceCodeFor(id);
  }

  static Future<File> _file() async =>
      File('${await getDatabasesPath()}/activation');

  static Future<bool> isActivated() async {
    final file = await _file();
    if (!await file.exists()) return false;
    return verifyActivation(
      await deviceCode(),
      await file.readAsString(),
      activationPublicKey,
    );
  }

  /// Check [code] and, only if it is valid for this tablet, keep it.
  static Future<bool> activate(String code) async {
    if (!await verifyActivation(
      await deviceCode(),
      code,
      activationPublicKey,
    )) {
      return false;
    }
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(normalise(code), flush: true);
    return true;
  }
}
