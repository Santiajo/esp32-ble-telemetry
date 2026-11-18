package com.example.esp32_ble_telemetry

import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Epu: en Android 11 o anterior la búsqueda Bluetooth no devuelve nada con la
    // Ubicación apagada (aunque el permiso esté dado). La app lo revisa y, si hace
    // falta, abre el ajuste de Ubicación (prueba en tablet Samsung, 18-11-2026).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "epu/sistema").setMethodCallHandler { call, result ->
            when (call.method) {
                "versionAndroid" -> result.success(Build.VERSION.SDK_INT)
                "ubicacionEncendida" -> {
                    val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                    val on = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) lm.isLocationEnabled
                    else lm.isProviderEnabled(LocationManager.GPS_PROVIDER) || lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
                    result.success(on)
                }
                "abrirAjusteUbicacion" -> {
                    startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
