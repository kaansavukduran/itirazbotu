import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:itiraz_botu/src/llm/gguf_inspector.dart';
import 'package:itiraz_botu/src/llm/model_store.dart';

/// Geçerli başlıklı, küçük bir sahte GGUF (1 tensör, 4 KB veri).
Uint8List fakeGguf({int dataBytes = 4096, String arch = 'llama'}) {
  final b = BytesBuilder();
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u64(int v) => b.add((ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List());
  void str(String s) {
    final e = s.codeUnits;
    u64(e.length);
    b.add(e);
  }

  u32(0x46554747);
  u32(3);
  u64(1); // tensör
  u64(2); // kv
  str('general.architecture');
  u32(8);
  str(arch);
  str('tokenizer.chat_template');
  u32(8);
  str('{{ x }}');
  str('w');
  u32(1);
  u64(dataBytes ~/ 4);
  u32(0);
  u64(0);
  while (b.length % 32 != 0) {
    b.addByte(0);
  }
  b.add(Uint8List(dataBytes));
  return b.toBytes();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('itiraz_store'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ModelStore store({int free = 1 << 40}) => ModelStore(Directory('${tmp.path}/models'), freeDiskOf: (_) => free);

  File src(String name, Uint8List data) => File('${tmp.path}/$name')..writeAsBytesSync(data);

  test('sahte GGUF incelenir', () {
    final info = inspectGgufSync(src('a.gguf', fakeGguf()).path);
    expect(info.architecture, 'llama');
    expect(info.hasChatTemplate, isTrue);
    expect(info.warnings, isEmpty);
  });

  test('içe aktarma ilerleme bildirir ve dosyayı kopyalar', () async {
    final data = fakeGguf(dataBytes: 3 * 1024 * 1024);
    final s = store();
    final progress = <double>[];
    final m = await s.importFile(src('Türkçe ağ modeli.gguf', data).path, onProgress: (d, t) => progress.add(d / t));
    expect(File(m.path).lengthSync(), data.length);
    expect(m.fileName, 'Türkçe ağ modeli.gguf');
    expect(progress.last, 1.0);
    expect(progress.length, greaterThan(1));
    expect((await s.list()).single.fileName, 'Türkçe ağ modeli.gguf');
  });

  test('aynı ad ikinci kez içe aktarılınca üzerine yazılmaz', () async {
    final s = store();
    final f = src('m.gguf', fakeGguf());
    await s.importFile(f.path);
    final second = await s.importFile(f.path);
    expect(second.fileName, 'm-2.gguf');
  });

  test('iptal yarım dosyayı siler', () async {
    final s = store();
    final token = CancelToken();
    final f = src('b.gguf', fakeGguf(dataBytes: 8 * 1024 * 1024));
    await expectLater(
      s.importFile(
        f.path,
        cancel: token,
        onProgress: (d, t) {
          if (d > 0) token.cancel();
        },
      ),
      throwsA(isA<ImportCancelled>()),
    );
    expect(Directory('${tmp.path}/models').listSync(), isEmpty);
  });

  test('yetersiz boş alan Türkçe hatayla reddedilir', () async {
    final s = store(free: 1024);
    await expectLater(
      s.importFile(src('c.gguf', fakeGguf()).path),
      throwsA(predicate((e) => e is ImportFailure && e.message.contains('Yeterli boş alan yok'))),
    );
  });

  test('GGUF olmayan dosya içe aktarılmaz', () async {
    final s = store();
    final f = File('${tmp.path}/resim.gguf')..writeAsBytesSync(List.filled(200, 7));
    await expectLater(
      s.importFile(f.path),
      throwsA(predicate((e) => e is ImportFailure && e.message.contains('GGUF model dosyası değil'))),
    );
  });

  test('kesik dosya içe aktarılmaz', () async {
    final data = fakeGguf(dataBytes: 4096);
    final f = src('kesik.gguf', Uint8List.sublistView(data, 0, data.length - 4096));
    await expectLater(
      store().importFile(f.path),
      throwsA(predicate((e) => e is ImportFailure && e.message.contains('yarım'))),
    );
  });

  test('son tensörün tek baytı eksik olsa da içe aktarılmaz', () async {
    final data = fakeGguf();
    final f = src('son-bayt-eksik.gguf', Uint8List.sublistView(data, 0, data.length - 1));
    await expectLater(store().importFile(f.path), throwsA(isA<ImportFailure>()));
  });

  test('desteklenmeyen sürüm ve bilinmeyen mimari', () {
    final data = fakeGguf(arch: 'gizemli');
    expect(inspectGgufSync(src('g.gguf', data).path).warnings.single, contains('denenmedi'));
    final v9 = Uint8List.fromList(data)..[4] = 9;
    expect(
      () => inspectGgufSync(src('v9.gguf', v9).path),
      throwsA(predicate((e) => e is GgufException && e.message.contains('sürüm 9'))),
    );
  });

  test('paketteki model parçalardan hazırlanır', () async {
    final data = fakeGguf(dataBytes: 10000);
    final half = data.length ~/ 2;
    final assets = {
      'assets/bundled_model/p0': ByteData.sublistView(Uint8List.sublistView(data, 0, half)),
      'assets/bundled_model/p1': ByteData.sublistView(Uint8List.sublistView(data, half)),
    };
    final manifest = BundledModelManifest(
      fileName: 'mini.gguf',
      size: data.length,
      parts: ['p0', 'p1'],
      displayName: 'Mini',
    );
    final s = store();
    expect(s.preparedBundled(manifest), isNull);
    final m = await s.prepareBundled(manifest, (k) async => assets[k]!);
    expect(m.bundled, isTrue);
    expect(File(m.path).readAsBytesSync(), data);
    expect(s.preparedBundled(manifest), isNotNull);
  });

  test('manifest yoksa paket modelsiz sayılır', () async {
    expect(await ModelStore.readManifest((k) async => throw Exception('yok')), isNull);
  });

  test('son paket parçasından sonra iptal dosyayı yayımlamaz', () async {
    final data = fakeGguf();
    final s = store();
    final token = CancelToken();
    final manifest = BundledModelManifest(fileName: 'mini.gguf', size: data.length, parts: ['p0']);
    await expectLater(
      s.prepareBundled(
        manifest,
        (_) async => ByteData.sublistView(data),
        cancel: token,
        onProgress: (_, _) => token.cancel(),
      ),
      throwsA(isA<ImportCancelled>()),
    );
    expect(s.dir.listSync(), isEmpty);
  });

  test('boyutu doğru ama bozuk paket modeli reddedilir', () async {
    final s = store();
    final manifest = BundledModelManifest(fileName: 'bozuk.gguf', size: 256, parts: ['p0']);
    await expectLater(s.prepareBundled(manifest, (_) async => ByteData(256)), throwsA(isA<ImportFailure>()));
    expect(s.dir.listSync(), isEmpty);
  });

  test('paket modelinin SHA-256 özeti uyuşmazsa yarım dosya silinir', () async {
    final data = fakeGguf();
    final s = store();
    final manifest = BundledModelManifest(fileName: 'mini.gguf', size: data.length, parts: ['p0'], sha256Hex: '0' * 64);
    await expectLater(
      s.prepareBundled(manifest, (_) async => ByteData.sublistView(data)),
      throwsA(predicate((e) => e is ImportFailure && e.message.contains('bütünlük'))),
    );
    expect(s.dir.listSync(), isEmpty);
  });

  test('bayt biçimlendirme Türkçe ondalık kullanır', () {
    expect(formatBytes(1536), '1,5 KB');
    expect(formatBytes(-1), 'bilinmiyor');
  });
}
