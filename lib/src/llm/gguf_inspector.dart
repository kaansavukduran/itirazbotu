/// GGUF dosya başlığını ağ ve model kütüphanesi olmadan inceler.
///
/// Amaç, kullanıcı bir dosyayı içe aktarmadan önce açık bir Türkçe hata vermek:
/// "bu GGUF değil", "dosya yarım kalmış", "mimari denenmemiş" gibi.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

/// Bu llama.cpp sürümüyle (b11900) denenmiş ya da yaygın küçük model mimarileri.
const Set<String> knownArchitectures = {
  'llama', 'qwen2', 'qwen3', 'qwen2moe', 'qwen3moe', 'gemma', 'gemma2', 'gemma3',
  'gemma3n', 'phi2', 'phi3', 'granite', 'granitemoe', 'smollm3', 'olmo', 'olmo2',
  'stablelm', 'starcoder2', 'deepseek2', 'exaone', 'lfm2', 'mistral3', 'cohere2',
};

class GgufInfo {
  GgufInfo({
    required this.version,
    required this.tensorCount,
    required this.fileSize,
    this.architecture,
    this.name,
    this.sizeLabel,
    this.contextLength,
    this.hasChatTemplate = false,
    this.warnings = const [],
  });

  final int version;
  final int tensorCount;
  final int fileSize;
  final String? architecture;
  final String? name;
  final String? sizeLabel;
  final int? contextLength;
  final bool hasChatTemplate;
  final List<String> warnings;

  String get displayName => name?.trim().isNotEmpty == true ? name!.trim() : 'Adsız model';
}

/// İnceleme hatası; [message] doğrudan kullanıcıya gösterilir.
class GgufException implements Exception {
  const GgufException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Dosyayı ayrı bir isolate'te inceler (arayüz donmaz).
Future<GgufInfo> inspectGgufFile(String path) => Isolate.run(() => inspectGgufSync(path));

class _Reader {
  _Reader(this._f, this.length);
  final RandomAccessFile _f;
  final int length;
  Uint8List _buf = Uint8List(0);
  int _bufStart = 0;
  int _pos = 0;

  int get position => _pos;

  void _ensure(int n) {
    if (_pos + n > length) throw const GgufException('Dosya beklenenden kısa: indirme ya da kopyalama yarım kalmış olabilir.');
    if (_pos >= _bufStart && _pos + n <= _bufStart + _buf.length) return;
    _f.setPositionSync(_pos);
    final want = n > 1 << 16 ? n : 1 << 16;
    _buf = _f.readSync(want);
    _bufStart = _pos;
    if (_buf.length < n) throw const GgufException('Dosya beklenenden kısa: indirme ya da kopyalama yarım kalmış olabilir.');
  }

  ByteData _view(int n) {
    _ensure(n);
    final off = _pos - _bufStart;
    _pos += n;
    return ByteData.sublistView(_buf, off, off + n);
  }

  int u8() => _view(1).getUint8(0);
  int u16() => _view(2).getUint16(0, Endian.little);
  int u32() => _view(4).getUint32(0, Endian.little);
  int u64() => _view(8).getUint64(0, Endian.little);
  int i64() => _view(8).getInt64(0, Endian.little);

  void skip(int n) {
    if (n < 0 || _pos + n > length) {
      throw const GgufException('Dosya beklenenden kısa: indirme ya da kopyalama yarım kalmış olabilir.');
    }
    _pos += n;
  }

  String str() {
    final n = u64();
    if (n > 64 * 1024 * 1024) throw const GgufException('Model üstverisi bozuk görünüyor.');
    _ensure(n);
    final off = _pos - _bufStart;
    _pos += n;
    return utf8.decode(Uint8List.sublistView(_buf, off, off + n), allowMalformed: true);
  }

  void skipStr() => skip(u64());
}

// GGUF değer türleri.
const _scalarSizes = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8};
const _tString = 8;
const _tArray = 9;

/// Eşzamanlı inceleme; testlerde doğrudan çağrılabilir.
GgufInfo inspectGgufSync(String path) {
  final file = File(path);
  if (!file.existsSync()) throw const GgufException('Dosya bulunamadı.');
  final size = file.lengthSync();
  if (size < 32) throw const GgufException('Bu bir GGUF model dosyası değil (dosya çok küçük).');
  final raf = file.openSync();
  try {
    final r = _Reader(raf, size);
    final magic = r.u32();
    if (magic != 0x46554747) {
      throw const GgufException('Bu bir GGUF model dosyası değil. Uzantısı .gguf olan bir dosya seçin.');
    }
    final version = r.u32();
    if (version < 2 || version > 3) {
      throw GgufException('GGUF sürüm $version desteklenmiyor. Daha yeni bir dönüştürücüyle hazırlanmış model deneyin.');
    }
    final tensorCount = r.u64();
    final kvCount = r.u64();
    if (tensorCount <= 0 || tensorCount > 1 << 20 || kvCount > 1 << 20) {
      throw const GgufException('Model üstverisi bozuk görünüyor.');
    }

    String? arch, name, sizeLabel;
    int? ctx;
    var alignment = 32;
    var hasTemplate = false;

    Object? readValue(int type) {
      if (type == _tString) return r.str();
      if (type == _tArray) {
        final sub = r.u32();
        final n = r.u64();
        if (sub == _tString) {
          for (var i = 0; i < n; i++) {
            r.skipStr();
          }
        } else {
          final s = _scalarSizes[sub];
          if (s == null) throw const GgufException('Model üstverisi bozuk görünüyor.');
          r.skip(s * n);
        }
        return null;
      }
      switch (type) {
        case 0:
          return r.u8();
        case 4:
          return r.u32();
        case 5:
          return r.u32().toSigned(32);
        case 10:
          return r.u64();
        case 11:
          return r.i64();
        default:
          final s = _scalarSizes[type];
          if (s == null) throw const GgufException('Model üstverisi bozuk görünüyor.');
          r.skip(s);
          return null;
      }
    }

    for (var i = 0; i < kvCount; i++) {
      final key = r.str();
      final type = r.u32();
      final val = readValue(type);
      if (key == 'general.architecture' && val is String) arch = val;
      if (key == 'general.name' && val is String) name = val;
      if (key == 'general.size_label' && val is String) sizeLabel = val;
      if (key == 'general.alignment' && val is int && val > 0) alignment = val;
      if (key == 'tokenizer.chat_template') hasTemplate = true;
      if (arch != null && key == '$arch.context_length' && val is int) ctx = val;
    }

    // Tensör bilgileri: en büyük ofset dosyanın içinde mi?
    var maxOffset = 0;
    for (var i = 0; i < tensorCount; i++) {
      r.skipStr();
      final nDims = r.u32();
      if (nDims > 8) throw const GgufException('Model üstverisi bozuk görünüyor.');
      r.skip(8 * nDims);
      r.u32(); // tür
      final off = r.u64();
      if (off > maxOffset) maxOffset = off;
    }
    final dataStart = (r.position + alignment - 1) ~/ alignment * alignment;
    if (dataStart + maxOffset >= size) {
      throw const GgufException('Model dosyası yarım: ağırlık verisi eksik. Dosyayı yeniden kopyalayın.');
    }

    final warnings = <String>[];
    if (arch == null) {
      warnings.add('Model mimarisi belirtilmemiş; yükleme başarısız olabilir.');
    } else if (!knownArchitectures.contains(arch)) {
      warnings.add('"$arch" mimarisi bu sürümde denenmedi; yükleme başarısız olabilir.');
    }
    if (!hasTemplate) {
      warnings.add('Modelde sohbet şablonu yok; yanıtlar daha dağınık olabilir.');
    }
    return GgufInfo(
      version: version,
      tensorCount: tensorCount,
      fileSize: size,
      architecture: arch,
      name: name,
      sizeLabel: sizeLabel,
      contextLength: ctx,
      hasChatTemplate: hasTemplate,
      warnings: warnings,
    );
  } on GgufException {
    rethrow;
  } on FileSystemException {
    throw const GgufException('Dosya okunamadı. Erişim iznini kontrol edin.');
  } finally {
    raf.closeSync();
  }
}

/// Bayt sayısını Türkçe okunur biçime çevirir ("1,2 GB").
String formatBytes(int bytes) {
  if (bytes < 0) return 'bilinmiyor';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final s = i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(v >= 100 ? 0 : 1);
  return '${s.replaceAll('.', ',')} ${units[i]}';
}
