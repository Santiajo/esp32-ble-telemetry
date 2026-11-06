import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';

/// Permisos para buscar y conectar los sticks. Android 11 o anterior no encuentra
/// nada por BLE sin ubicación; en Android 12 o superior ese permiso no está en el
/// manifiesto (`maxSdkVersion` 30), así que el teléfono no pregunta.
Future<bool> ensureBlePermissions() async {
  if (!Platform.isAndroid) return true;
  final scan = await Permission.bluetoothScan.request();
  final connect = await Permission.bluetoothConnect.request();
  await Permission.locationWhenInUse.request();
  return scan.isGranted && connect.isGranted;
}
