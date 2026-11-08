/// Cihazdaki model dosyalarını yönetir: içe aktarma, listeleme, silme ve
/// uygulamayla birlikte gelen ("model dâhil" paket) modeli hazırlama.
///
/// Hiçbir işlem ağ kullanmaz; kaynak her zaman yerel bir dosya ya da uygulama paketidir.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'gguf_inspector.dart';

/// İçe aktarma ya da hazırlama sırasında iptal için.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class ImportCancelled implements Exception {
  const ImportCancelled();
  String get message => 'İçe aktarma iptal edildi; yarım kalan dosya silindi.';
  @override
  String toString() => message;
}

class ImportFailure implements Exception {
  const ImportFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cihazda kayıtlı bir model.
class StoredModel {
  StoredModel({required this.path, required this.size, this.bundled = false});
  final String path;
  final int size;
  final bool bundled;
  String get fileName => path.split(Platform.pathSeparator).last;
}

/// Paketle gelen modelin tanımı (assets/bundled_model/manifest.json).
class BundledModelManifest {
  BundledModelManifest({required this.fileName, required this.size, required this.parts, this.displayName, this.license});

  factory BundledModelManifest.fromJson(Map<String, dynamic> j) => BundledModelManifest(
        fileName: j['file'] as String,
        size: j['size'] as int,
        parts: (j['parts'] as List).cast<String>(),
        displayName: j['name'] as String?,
        license: j['license'] as String?,
      );

  final String fileName;
  final int size;
  final List<String> parts;
  final String? displayName;
  final String? license;
}

/// Asset okuyucu: testlerde sahte, uygulamada `rootBundle.load`.
typedef AssetLoader = Future<ByteData> Function(String key);

class ModelStore {
  ModelStore(this.dir, {required this.freeDiskOf});

  /// Modellerin tutulduğu dizin (uygulama destek dizini/models).
  final Directory dir;

  /// Boş alan ölçer (bayt, bilinmiyorsa -1).
  final int Function(String path) freeDiskOf;

  /// Güvenlik payı: dosya sistemi ve geçici dosyalar için.
  static const int safetyMargin = 64 * 1024 * 1024;

  Future<List<StoredModel>> list() async {
    if (!dir.existsSync()) return [];
    final out = <StoredModel>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.gguf')) {
        out.add(StoredModel(path: e.path, size: e.lengthSync(), bundled: e.path.contains('${Platform.pathSeparator}paket_')));
      }
    }
    out.sort((a, b) => a.fileName.compareTo(b.fileName));
    return out;
  }

  Future<void> delete(StoredModel m) async {
    final f = File(m.path);
    if (f.existsSync()) await f.delete();
  }

  void _checkSpace(int need) {
    dir.createSync(recursive: true);
    final free = freeDiskOf(dir.path);
    if (free >= 0 && free < need + safetyMargin) {
      throw ImportFailure('Yeterli boş alan yok: ${formatBytes(need + safetyMargin)} gerekli, '
          '${formatBytes(free)} boş. Yer açıp yeniden deneyin.');
    }
  }

  String _uniqueTarget(String name) {
    var safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (!safe.toLowerCase().endsWith('.gguf')) safe = '$safe.gguf';
    var target = '${dir.path}${Platform.pathSeparator}$safe';
    var i = 2;
    while (File(target).existsSync()) {
      target = '${dir.path}${Platform.pathSeparator}${safe.substring(0, safe.length - 5)}-$i.gguf';
      i++;
    }
    return target;
  }

  /// Yerel bir GGUF dosyasını model dizinine kopyalar.
  ///
  /// Önce biçim ve boş alan denetlenir; [onProgress] (kopyalanan, toplam) bildirir.
  /// İptal edilirse yarım dosya silinir ve [ImportCancelled] fırlatılır.
  Future<StoredModel> importFile(
    String sourcePath, {
    void Function(int done, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final src = File(sourcePath);
    if (!src.existsSync()) throw const ImportFailure('Seçilen dosya bulunamadı.');
    try {
      await inspectGgufFile(sourcePath);
    } on GgufException catch (e) {
      throw ImportFailure(e.message);
    }
    final total = src.lengthSync();
    _checkSpace(total);
    final target = _uniqueTarget(src.uri.pathSegments.last);
    final part = File('$target.part');
    final sink = part.openWrite();
    var done = 0;
    try {
      await for (final chunk in src.openRead()) {
        if (cancel?.isCancelled == true) throw const ImportCancelled();
        sink.add(chunk);
        done += chunk.length;
        onProgress?.call(done, total);
      }
      await sink.flush();
      await sink.close();
      if (cancel?.isCancelled == true) throw const ImportCancelled();
      if (part.lengthSync() != total) {
        throw const ImportFailure('Kopyalama eksik kaldı; dosya yeniden denenmeli.');
      }
      await part.rename(target);
      return StoredModel(path: target, size: total);
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (part.existsSync()) await part.delete();
      if (e is ImportCancelled || e is ImportFailure) rethrow;
      if (e is FileSystemException) {
        throw ImportFailure('Dosya kopyalanamadı: ${e.osError?.message ?? e.message}');
      }
      rethrow;
    }
  }

  /// Paketteki modelin manifestini okur; paket modelsizse `null`.
  static Future<BundledModelManifest?> readManifest(AssetLoader load) async {
    try {
      final data = await load('assets/bundled_model/manifest.json');
      final j = jsonDecode(utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
      if (j is Map<String, dynamic> && j['file'] is String) return BundledModelManifest.fromJson(j);
    } catch (_) {}
    return null;
  }

  /// Paketteki modelin hazırlanmış kopyası varsa onu döndürür.
  StoredModel? preparedBundled(BundledModelManifest m) {
    final f = File('${dir.path}${Platform.pathSeparator}paket_${m.fileName}');
    if (f.existsSync() && f.lengthSync() == m.size) return StoredModel(path: f.path, size: m.size, bundled: true);
    return null;
  }

  /// Paketteki modeli parçalardan birleştirip model dizinine yazar (ağ yok).
  /// Parçalar en fazla 64 MB olduğu için bellek kullanımı sınırlı kalır.
  Future<StoredModel> prepareBundled(
    BundledModelManifest m,
    AssetLoader load, {
    void Function(int done, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final ready = preparedBundled(m);
    if (ready != null) return ready;
    _checkSpace(m.size);
    final target = File('${dir.path}${Platform.pathSeparator}paket_${m.fileName}');
    final part = File('${target.path}.part');
    final sink = part.openWrite();
    var done = 0;
    try {
      for (final p in m.parts) {
        if (cancel?.isCancelled == true) throw const ImportCancelled();
        final data = await load('assets/bundled_model/$p');
        sink.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        await sink.flush();
        done += data.lengthInBytes;
        onProgress?.call(done, m.size);
      }
      await sink.close();
      if (part.lengthSync() != m.size) throw const ImportFailure('Paketteki model eksik; uygulamayı yeniden kurun.');
      await part.rename(target.path);
      return StoredModel(path: target.path, size: m.size, bundled: true);
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (part.existsSync()) await part.delete();
      rethrow;
    }
  }
}
