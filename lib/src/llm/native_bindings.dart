/// `itiraz_native` köprü kütüphanesinin dart:ffi bağlantıları.
///
/// C tarafı: native/itiraz_native.cpp. llama.cpp sürümü third_party/llama.cpp
/// alt modülünde sabitlenmiştir; bu dosya yalnızca köprünün sade C yüzeyini görür.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Köprünün beklenen ABI sürümü (C tarafındaki kAbiVersion ile aynı olmalı).
const int expectedAbiVersion = 2;

/// `ib_next` dönüş değeri: üretim bitti.
const int ibDone = -100;

/// `ib_next` dönüş değeri: üretim iptal edildi.
const int ibCancelled = -1;

typedef IbLoadC = Pointer<Void> Function(
  Pointer<Utf8>,
  Int32,
  Int32,
  Pointer<Float>,
  Pointer<Int32>,
  Pointer<Utf8>,
  Int32,
);
typedef IbLoadDart = Pointer<Void> Function(
  Pointer<Utf8>,
  int,
  int,
  Pointer<Float>,
  Pointer<Int32>,
  Pointer<Utf8>,
  int,
);
typedef IbStartC = Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, Int32, Float, Uint32);
typedef IbStartDart = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>, int, double, int);
typedef IbNextC = Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32);
typedef IbNextDart = int Function(Pointer<Void>, Pointer<Uint8>, int);

/// Yüklenmiş köprü kütüphanesi.
class NativeBridge {
  NativeBridge._(DynamicLibrary lib)
    : abiVersion = lib.lookupFunction<Int32 Function(), int Function()>('ib_abi_version'),
      load = lib.lookupFunction<IbLoadC, IbLoadDart>('ib_load'),
      free = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('ib_free'),
      cancel = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('ib_cancel'),
      prepareGeneration = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
        'ib_prepare_generation',
      ),
      modelSize = lib.lookupFunction<Int64 Function(Pointer<Void>), int Function(Pointer<Void>)>('ib_model_size'),
      lastError = lib.lookupFunction<Pointer<Utf8> Function(Pointer<Void>), Pointer<Utf8> Function(Pointer<Void>)>(
        'ib_last_error',
      ),
      start = lib.lookupFunction<IbStartC, IbStartDart>('ib_start'),
      next = lib.lookupFunction<IbNextC, IbNextDart>('ib_next'),
      freeDisk = lib.lookupFunction<Int64 Function(Pointer<Utf8>), int Function(Pointer<Utf8>)>('ib_free_disk'),
      availableRam = lib.lookupFunction<Int64 Function(), int Function()>('ib_available_ram');

  final int Function() abiVersion;
  final IbLoadDart load;
  final void Function(Pointer<Void>) free;
  final void Function(Pointer<Void>) cancel;
  final void Function(Pointer<Void>) prepareGeneration;
  final int Function(Pointer<Void>) modelSize;
  final Pointer<Utf8> Function(Pointer<Void>) lastError;
  final IbStartDart start;
  final IbNextDart next;
  final int Function(Pointer<Utf8>) freeDisk;
  final int Function() availableRam;

  static NativeBridge? _cached;
  static String? _loadError;

  /// Kütüphaneyi açmayı dener; açılamazsa `null` döner ve [loadError] doldurulur.
  static NativeBridge? tryOpen() {
    if (_cached != null) return _cached;
    if (_loadError != null) return null;
    try {
      final b = NativeBridge._(_openLibrary());
      final v = b.abiVersion();
      if (v != expectedAbiVersion) {
        _loadError = 'Yerel model kütüphanesinin sürümü uyumsuz (beklenen $expectedAbiVersion, bulunan $v).';
        return null;
      }
      return _cached = b;
    } catch (e) {
      _loadError = 'Yerel model kütüphanesi bu kurulumda bulunamadı.';
      return null;
    }
  }

  static String? get loadError => _loadError;

  /// Testlerde kütüphane yolunu elle vermek için.
  static String? overridePath = Platform.environment['ITIRAZ_NATIVE_LIB'];

  static DynamicLibrary _openLibrary() {
    final override = overridePath;
    if (override != null && override.isNotEmpty) {
      return DynamicLibrary.open(override);
    }
    if (Platform.isIOS || Platform.isMacOS) {
      // CocoaPods ile gömülen çerçeve (bkz. native/apple/ItirazNative.podspec).
      try {
        return DynamicLibrary.open('itiraz_native.framework/itiraz_native');
      } catch (_) {
        return DynamicLibrary.process();
      }
    }
    if (Platform.isWindows) return DynamicLibrary.open('itiraz_native.dll');
    if (Platform.isAndroid) return DynamicLibrary.open('libitiraz_native.so');
    // Linux: paket içindeki lib/ dizini.
    try {
      return DynamicLibrary.open('libitiraz_native.so');
    } catch (_) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      return DynamicLibrary.open('$exeDir/lib/libitiraz_native.so');
    }
  }
}
