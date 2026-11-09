/// Cihaz üzerinde llama.cpp ile çalışan yerel model hizmeti.
///
/// Model yükleme ve üretim ayrı bir isolate'te yapılır; arayüz donmaz. İptal,
/// ana isolate'ten doğrudan C köprüsüne (atomik bayrak) iletilir, böylece işçi
/// isolate uzun bir döngüdeyken bile hemen durur.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'gguf_inspector.dart';
import 'native_bindings.dart';

enum ModelState { unavailable, empty, loading, ready, generating, error }

/// Üretim akışındaki olaylar.
sealed class GenerationEvent {}

class GenerationChunk extends GenerationEvent {
  GenerationChunk(this.text);
  final String text;
}

class GenerationFinished extends GenerationEvent {
  GenerationFinished({required this.cancelled, this.error, this.tokenCount = 0});
  final bool cancelled;
  final String? error;
  final int tokenCount;
}

class ModelLoadException implements Exception {
  const ModelLoadException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
  @override
  String toString() => message;
}

/// Yerel model durumunu tutan ve işçi isolate'i yöneten hizmet.
class LocalModelService {
  LocalModelService({this.contextSize = 2048, this.threads = 0});

  final int contextSize;
  final int threads;

  NativeBridge? _bridge;
  Isolate? _isolate;
  SendPort? _toWorker;
  ReceivePort? _fromWorker;
  StreamController<Object?>? _replies;
  Stream<Object?>? _replyStream;
  Future<void>? _loading;
  bool _disposed = false;

  int _handle = 0;
  Pointer<Float>? _progress;
  Pointer<Int32>? _loadCancel;
  String? _loadedPath;
  String? loadedName;

  ModelState _state = ModelState.empty;
  ModelState get state => _state;
  String? lastError;

  final _stateCtrl = StreamController<ModelState>.broadcast();
  Stream<ModelState> get states => _stateCtrl.stream;

  void _set(ModelState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  /// Yerel kütüphane bu kurulumda var mı?
  bool get isSupported => (_bridge ??= NativeBridge.tryOpen()) != null;

  String? get unsupportedReason => isSupported ? null : NativeBridge.loadError;

  bool get isLoaded => _handle != 0;
  String? get loadedPath => _loadedPath;

  /// Kullanılabilir bellek (bayt); bilinmiyorsa -1.
  int availableRam() => isSupported ? _bridge!.availableRam() : -1;

  /// Verilen dizinin bulunduğu birimdeki boş alan; bilinmiyorsa -1.
  int freeDisk(String dir) {
    if (!isSupported) return -1;
    final p = dir.toNativeUtf8();
    try {
      return _bridge!.freeDisk(p);
    } finally {
      calloc.free(p);
    }
  }

  Future<void> _ensureWorker() async {
    if (_toWorker != null) return;
    _fromWorker = ReceivePort();
    _replies = StreamController<Object?>.broadcast();
    _replyStream = _replies!.stream;
    final ready = Completer<SendPort>();
    _fromWorker!.listen((msg) {
      if (msg is SendPort && !ready.isCompleted) {
        ready.complete(msg);
      } else {
        _replies!.add(msg);
      }
    });
    _isolate = await Isolate.spawn(_workerMain, [_fromWorker!.sendPort, NativeBridge.overridePath]);
    _toWorker = await ready.future;
  }

  /// Modeli yükler. [onProgress] 0..1 arası ilerleme bildirir.
  /// Bellek yetersizse, dosya bozuksa ya da iptal edilirse [ModelLoadException] fırlatır.
  Future<void> load(String path, {String? displayName, void Function(double)? onProgress}) {
    if (_disposed) {
      return Future<void>.error(const ModelLoadException('Model hizmeti kapatıldı.'));
    }
    if (!isSupported) {
      return Future<void>.error(ModelLoadException(unsupportedReason ?? 'Yerel model bu kurulumda desteklenmiyor.'));
    }
    if (_state == ModelState.loading || _state == ModelState.generating) {
      return Future<void>.error(const ModelLoadException('Önce süren işlemin bitmesini bekleyin.'));
    }
    _progress ??= calloc<Float>();
    _loadCancel ??= calloc<Int32>();
    _progress!.value = 0;
    _loadCancel!.value = 0;
    _set(ModelState.loading);
    final operation = _load(path, displayName: displayName, onProgress: onProgress);
    _loading = operation;
    return operation.whenComplete(() => _loading = null);
  }

  void _checkLoadCancelled() {
    if (_loadCancel!.value != 0) {
      throw const ModelLoadException('Model yüklemesi iptal edildi.', cancelled: true);
    }
  }

  Future<void> _load(String path, {String? displayName, void Function(double)? onProgress}) async {
    Timer? timer;
    try {
      final file = File(path);
      if (!file.existsSync()) {
        throw const ModelLoadException('Model dosyası bulunamadı.');
      }

      // Önce başlığı denetle: bozuk dosyayı llama.cpp'ye hiç vermeyelim.
      try {
        await inspectGgufFile(path);
      } on GgufException catch (e) {
        lastError = e.message;
        _set(ModelState.error);
        throw ModelLoadException(e.message);
      }

      final size = file.lengthSync();
      final ram = availableRam();
      // Kabaca: ağırlıklar + bağlam önbelleği + çalışma alanı.
      final need = (size * 1.1).round() + 256 * 1024 * 1024;
      if (ram > 0 && need > ram) {
        lastError =
            'Cihaz belleği bu model için yetmiyor: yaklaşık ${formatBytes(need)} gerekli, '
            '${formatBytes(ram)} boş. Daha küçük bir model (ör. 0,5–1,5 milyar parametre, Q4) deneyin.';
        _set(ModelState.error);
        throw ModelLoadException(lastError!);
      }

      _checkLoadCancelled();
      await _unloadHandle();
      await _ensureWorker();
      _checkLoadCancelled();

      timer = Timer.periodic(const Duration(milliseconds: 100), (_) => onProgress?.call(_progress!.value));
      final reply = _replyStream!.firstWhere((m) => m is Map && m['op'] == 'loaded');
      _toWorker!.send({
        'op': 'load',
        'path': path,
        'ctx': contextSize,
        'threads': threads > 0 ? threads : _defaultThreads(),
        'progress': _progress!.address,
        'cancel': _loadCancel!.address,
      });
      final res = await reply as Map;
      if (res['handle'] is int && res['handle'] != 0) {
        _handle = res['handle'] as int;
        if (_loadCancel!.value != 0) {
          await _unloadHandle();
          _checkLoadCancelled();
        }
        _loadedPath = path;
        loadedName = displayName ?? file.uri.pathSegments.last;
        lastError = null;
        onProgress?.call(1);
        _set(ModelState.ready);
      } else {
        final cancelled = _loadCancel!.value != 0;
        lastError = res['error'] as String? ?? 'Model açılamadı.';
        _set(cancelled ? ModelState.empty : ModelState.error);
        throw ModelLoadException(lastError!, cancelled: cancelled);
      }
    } on ModelLoadException catch (e) {
      lastError = e.message;
      _set(e.cancelled ? (isLoaded ? ModelState.ready : ModelState.empty) : ModelState.error);
      rethrow;
    } on FileSystemException {
      lastError = 'Model dosyası okunamadı. Dosyanın erişim iznini kontrol edin.';
      _set(ModelState.error);
      throw ModelLoadException(lastError!);
    } finally {
      timer?.cancel();
    }
  }

  /// Süren model yüklemesini iptal eder.
  void cancelLoad() {
    if (_state == ModelState.loading) _loadCancel?.value = 1;
  }

  /// [user] mesajı için yanıt üretir. Akış, [GenerationFinished] ile biter.
  Stream<GenerationEvent> generate({
    required String system,
    required String user,
    int maxTokens = 320,
    double temperature = 0.4,
  }) {
    final out = StreamController<GenerationEvent>();
    if (_handle == 0 || _state != ModelState.ready) {
      out
        ..add(GenerationFinished(cancelled: false, error: 'Önce ayarlardan bir model yükleyin.'))
        ..close();
      return out.stream;
    }
    _set(ModelState.generating);
    // İptal bayrağını işçiye işi yollamadan sıfırla: aynı turda gelen Durdur
    // isteği ib_start tarafından yanlışlıkla silinmesin.
    _bridge!.prepareGeneration(Pointer<Void>.fromAddress(_handle));
    final id = DateTime.now().microsecondsSinceEpoch;
    late StreamSubscription<Object?> sub;
    sub = _replyStream!.listen((m) {
      if (m is! Map || m['id'] != id) return;
      if (m['op'] == 'chunk') {
        out.add(GenerationChunk(m['text'] as String));
      } else if (m['op'] == 'done') {
        out.add(
          GenerationFinished(
            cancelled: m['cancelled'] == true,
            error: m['error'] as String?,
            tokenCount: m['tokens'] as int? ?? 0,
          ),
        );
        sub.cancel();
        out.close();
        _set(_handle != 0 ? ModelState.ready : ModelState.empty);
      }
    });
    _toWorker!.send({
      'op': 'gen',
      'id': id,
      'handle': _handle,
      'system': system,
      'user': user,
      'max': maxTokens,
      'temp': temperature,
    });
    return out.stream;
  }

  /// Süren üretimi durdurur (ana isolate'ten, beklemeden).
  void stop() {
    if (_handle != 0 && _state == ModelState.generating) {
      _bridge!.cancel(Pointer<Void>.fromAddress(_handle));
    }
  }

  /// Modeli bellekten çıkarır.
  Future<void> unload() async {
    if (_loading != null) {
      cancelLoad();
      try {
        await _loading;
      } on ModelLoadException catch (_) {}
    }
    await _unloadHandle();
    _set(ModelState.empty);
  }

  Future<void> _unloadHandle() async {
    if (_handle == 0) return;
    stop();
    final h = _handle;
    _handle = 0;
    _loadedPath = null;
    loadedName = null;
    final done = _replyStream!.firstWhere((m) => m is Map && m['op'] == 'freed');
    _toWorker!.send({'op': 'free', 'handle': h});
    await done;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await unload();
    _toWorker?.send({'op': 'exit'});
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _fromWorker?.close();
    await _replies?.close();
    if (_progress != null) calloc.free(_progress!);
    if (_loadCancel != null) calloc.free(_loadCancel!);
    await _stateCtrl.close();
  }

  static int _defaultThreads() {
    final n = Platform.numberOfProcessors;
    if (n <= 2) return 1;
    return n > 8 ? 6 : n - 1;
  }
}

/// İşçi isolate: tüm engelleyici FFI çağrıları burada yapılır.
void _workerMain(List<Object?> args) {
  final toMain = args[0] as SendPort;
  NativeBridge.overridePath = args[1] as String?;
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  final bridge = NativeBridge.tryOpen();

  inbox.listen((msg) {
    final m = msg as Map;
    switch (m['op']) {
      case 'load':
        if (bridge == null) {
          toMain.send({'op': 'loaded', 'handle': 0, 'error': NativeBridge.loadError});
          return;
        }
        final path = (m['path'] as String).toNativeUtf8();
        final err = calloc<Uint8>(512);
        try {
          final h = bridge.load(
            path,
            m['ctx'] as int,
            m['threads'] as int,
            Pointer<Float>.fromAddress(m['progress'] as int),
            Pointer<Int32>.fromAddress(m['cancel'] as int),
            err.cast<Utf8>(),
            512,
          );
          toMain.send({
            'op': 'loaded',
            'handle': h.address,
            'error': h.address == 0 ? err.cast<Utf8>().toDartString() : null,
          });
        } finally {
          calloc.free(path);
          calloc.free(err);
        }
      case 'gen':
        _generate(bridge!, m, toMain);
      case 'free':
        bridge?.free(Pointer<Void>.fromAddress(m['handle'] as int));
        toMain.send({'op': 'freed'});
      case 'exit':
        inbox.close();
    }
  });
}

void _generate(NativeBridge b, Map m, SendPort toMain) {
  final id = m['id'];
  final h = Pointer<Void>.fromAddress(m['handle'] as int);
  final sys = (m['system'] as String).toNativeUtf8();
  final usr = (m['user'] as String).toNativeUtf8();
  const bufLen = 256;
  final buf = calloc<Uint8>(bufLen);
  var tokens = 0;
  // Belirteçler UTF-8 karakterin ortasında bölünebilir; akış çözücü bunları birleştirir.
  final pending = StringBuffer();
  final sink = const Utf8Decoder(allowMalformed: true).startChunkedConversion(_StringSink(pending));
  var lastFlush = DateTime.now();
  void flush() {
    if (pending.isEmpty) return;
    toMain.send({'op': 'chunk', 'id': id, 'text': pending.toString()});
    pending.clear();
    lastFlush = DateTime.now();
  }

  try {
    final rc = b.start(
      h,
      sys,
      usr,
      m['max'] as int,
      (m['temp'] as num).toDouble(),
      DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
    );
    if (rc == 1) {
      toMain.send({'op': 'done', 'id': id, 'cancelled': true});
      return;
    }
    if (rc != 0) {
      toMain.send({'op': 'done', 'id': id, 'cancelled': false, 'error': b.lastError(h).toDartString()});
      return;
    }
    while (true) {
      final n = b.next(h, buf, bufLen);
      if (n == ibDone || n == ibCancelled || n < 0) {
        sink.close();
        flush();
        toMain.send({
          'op': 'done',
          'id': id,
          'tokens': tokens,
          'cancelled': n == ibCancelled,
          'error': (n < 0 && n != ibDone && n != ibCancelled) ? b.lastError(h).toDartString() : null,
        });
        return;
      }
      tokens++;
      if (n > 0) sink.add(buf.asTypedList(n).toList());
      if (DateTime.now().difference(lastFlush).inMilliseconds > 40) flush();
    }
  } finally {
    calloc.free(sys);
    calloc.free(usr);
    calloc.free(buf);
  }
}

class _StringSink implements Sink<String> {
  _StringSink(this._b);
  final StringBuffer _b;
  @override
  void add(String data) => _b.write(data);
  @override
  void close() {}
}
