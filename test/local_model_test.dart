// Gerçek llama.cpp köprüsüyle uçtan uca yerel model testleri.
//
// Çalıştırmak için (Linux örneği):
//   cmake -S native -B build/native -G Ninja -DCMAKE_BUILD_TYPE=Release && ninja -C build/native itiraz_native
//   python3 tool/make_test_model.py build/test-model.gguf build/bozuk.gguf
//   ITIRAZ_NATIVE_LIB=$PWD/build/native/libitiraz_native.so \
//   ITIRAZ_TEST_MODEL=$PWD/build/test-model.gguf ITIRAZ_BAD_MODEL=$PWD/build/bozuk.gguf \
//   flutter test test/local_model_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:itiraz_botu/src/llm/gguf_inspector.dart';
import 'package:itiraz_botu/src/llm/local_model_service.dart';

void main() {
  final env = Platform.environment;
  final lib = env['ITIRAZ_NATIVE_LIB'];
  final model = env['ITIRAZ_TEST_MODEL'];
  final bad = env['ITIRAZ_BAD_MODEL'];
  final skip = (lib == null || model == null) ? 'ITIRAZ_NATIVE_LIB / ITIRAZ_TEST_MODEL tanımlı değil' : null;

  late LocalModelService svc;
  setUp(() => svc = LocalModelService(contextSize: 256, threads: 2));
  tearDown(() => svc.dispose());

  test('GGUF başlığı okunur', () {
    final info = inspectGgufSync(model!);
    expect(info.architecture, 'llama');
    expect(info.version, 3);
    expect(info.tensorCount, greaterThan(5));
  }, skip: skip);

  test('kesik dosya içe aktarmadan önce reddedilir', () {
    expect(() => inspectGgufSync(bad!), throwsA(isA<GgufException>()));
  }, skip: skip ?? (bad == null ? 'ITIRAZ_BAD_MODEL yok' : null));

  test('GGUF olmayan dosya Türkçe hata verir', () async {
    final f = File('${Directory.systemTemp.path}/sahte_model.gguf')
      ..writeAsStringSync('merhaba dünya, ben model değilim' * 4);
    try {
      expect(
        () => inspectGgufSync(f.path),
        throwsA(predicate((e) => e is GgufException && e.message.contains('GGUF model dosyası değil'))),
      );
      await expectLater(svc.load(f.path), throwsA(isA<ModelLoadException>()));
      expect(svc.state, ModelState.error);
    } finally {
      f.deleteSync();
    }
  }, skip: skip);

  test(
    'model yüklenir ve gerçek belirteç üretir',
    () async {
      expect(svc.isSupported, isTrue, reason: svc.unsupportedReason);
      final progress = <double>[];
      await svc.load(model!, onProgress: progress.add);
      expect(svc.state, ModelState.ready);
      expect(progress.last, 1.0);

      final events = await svc
          .generate(system: 'Kısa yanıt ver.', user: 'Özür mesajını kendim mi yazmalıyım?', maxTokens: 24)
          .toList();
      final fin = events.last as GenerationFinished;
      expect(fin.error, isNull);
      expect(fin.cancelled, isFalse);
      expect(fin.tokenCount, greaterThan(0));
      final text = events.whereType<GenerationChunk>().map((c) => c.text).join();
      // Rastgele ağırlıklı test modeli anlamsız metin üretir; önemli olan gerçekten üretmesi.
      expect(text, isNotEmpty);
      expect(svc.state, ModelState.ready);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'üretim kullanıcı tarafından durdurulur',
    () async {
      await svc.dispose();
      svc = LocalModelService(contextSize: 4096, threads: 1);
      await svc.load(model!);
      final events = <GenerationEvent>[];
      final done = Completer<void>();
      // İlk gerçek parçadan sonra yeterince uzun, sabit tohumlu bir üretimi
      // durdur. Hızlı CI makinesi 200 belirteci iki parçadan önce bitirebilir.
      svc.generate(system: '', user: 'Uzun bir hikâye anlat', maxTokens: 3000, temperature: 0.8, seed: 42).listen((e) {
        events.add(e);
        if (e is GenerationChunk) svc.stop();
        if (e is GenerationFinished) done.complete();
      });
      await done.future;
      final fin = events.last as GenerationFinished;
      expect(fin.cancelled, isTrue);
      expect(fin.tokenCount, lessThan(3000));
      expect(svc.state, ModelState.ready, reason: 'iptalden sonra model kullanılabilir kalmalı');
      // Ardından yeniden üretilebilir.
      final again = await svc.generate(system: '', user: 'Tekrar', maxTokens: 4).toList();
      expect((again.last as GenerationFinished).cancelled, isFalse);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('model yüklemesi iptal edilebilir', () async {
    final f = svc.load(model!);
    svc.cancelLoad();
    await expectLater(f, throwsA(predicate((e) => e is ModelLoadException && e.cancelled)));
    expect(svc.state, ModelState.empty);
  }, skip: skip);

  test('üretim başladığı turda gelen durdur isteği kaybolmaz', () async {
    await svc.load(model!);
    final events = svc.generate(system: '', user: 'Merhaba', maxTokens: 100).toList();
    svc.stop();
    final finished = (await events).last as GenerationFinished;
    expect(finished.cancelled, isTrue);
    expect(svc.state, ModelState.ready);
    final again = await svc.generate(system: '', user: 'Tekrar', maxTokens: 2).toList();
    expect((again.last as GenerationFinished).error, isNull);
  }, skip: skip);

  test('başlık denetlenirken ikinci yükleme reddedilir', () async {
    final first = svc.load(model!);
    await expectLater(svc.load(model), throwsA(isA<ModelLoadException>()));
    svc.cancelLoad();
    await expectLater(first, throwsA(predicate((e) => e is ModelLoadException && e.cancelled)));
  }, skip: skip);

  test('başlığı geçerli ama llama.cpp\'nin açamadığı model kurallı sonucu bozmaz', () async {
    final bytes = File(model!).readAsBytesSync();
    final needle = [5, 0, 0, 0, 0, 0, 0, 0, ...'llama'.codeUnits];
    var at = -1;
    for (var i = 0; i < bytes.length - needle.length && at < 0; i++) {
      var ok = true;
      for (var j = 0; j < needle.length && ok; j++) {
        ok = bytes[i + j] == needle[j];
      }
      if (ok) at = i;
    }
    expect(at, greaterThan(0));
    bytes[at + 12] = 'x'.codeUnitAt(0); // "llamx": bilinmeyen mimari
    final f = File('${Directory.systemTemp.path}/uyumsuz.gguf')..writeAsBytesSync(bytes);
    try {
      final info = inspectGgufSync(f.path);
      expect(info.warnings.join(), contains('denenmedi'));
      await expectLater(
        svc.load(f.path),
        throwsA(predicate((e) => e is ModelLoadException && e.message.contains('açılamadı'))),
      );
      expect(svc.state, ModelState.error);
      // Ardından geçerli model yine yüklenebilir.
      await svc.load(model);
      expect(svc.state, ModelState.ready);
    } finally {
      f.deleteSync();
    }
  }, skip: skip);

  test('bellekten çıkarma', () async {
    await svc.load(model!);
    await svc.unload();
    expect(svc.isLoaded, isFalse);
    final ev = await svc.generate(system: '', user: 'x').toList();
    expect((ev.single as GenerationFinished).error, contains('model yükleyin'));
  }, skip: skip);

  test('boş disk ve bellek ölçülür', () {
    expect(svc.freeDisk(Directory.systemTemp.path), greaterThan(0));
    expect(svc.availableRam(), greaterThan(0));
  }, skip: skip);
}
