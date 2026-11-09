// İsteğe bağlı, eğitimli modelle uçtan uca deneme. Rastgele test ağırlıkları
// Türkçe kalitesinin kanıtı sayılmaz. Ayrıntılar: docs/DOGRULAMA.md.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:itiraz_botu/src/core/rule_engine.dart';
import 'package:itiraz_botu/src/llm/gguf_inspector.dart';
import 'package:itiraz_botu/src/llm/local_model_service.dart';
import 'package:itiraz_botu/src/llm/model_store.dart';
import 'package:itiraz_botu/src/llm/prompt.dart';

void main() {
  final model = Platform.environment['ITIRAZ_REAL_MODEL'];
  test(
    'eğitimli GGUF yerelden aktarılır ve Türkçe görevler için yanıt üretir',
    () async {
      final dir = Directory.systemTemp.createTempSync('itiraz_real_');
      final svc = LocalModelService(contextSize: 2048, threads: 4);
      try {
        expect(svc.isSupported, isTrue, reason: svc.unsupportedReason);
        final store = ModelStore(dir, freeDiskOf: svc.freeDisk);
        final imported = await store.importFile(model!);
        final info = await inspectGgufFile(imported.path);
        expect(info.tensorCount, greaterThan(10));
        await svc.load(imported.path, displayName: info.displayName);
        final results = <Map<String, Object?>>[];
        for (final task in ['Arkadaşıma özür mesajı yaz.', 'Bu matematik sorusunu çöz.', 'Bu paragrafı sadeleştir.']) {
          final verdict = const RuleEngine().evaluate(task);
          final events = await svc
              .generate(
                system: refineSystemPrompt,
                user: buildRefinePrompt(task, verdict),
                maxTokens: 160,
                temperature: 0,
              )
              .toList();
          final finished = events.last as GenerationFinished;
          expect(finished.error, isNull);
          expect(finished.cancelled, isFalse);
          final text = cleanModelOutput(events.whereType<GenerationChunk>().map((e) => e.text).join());
          expect(text, isNotEmpty);
          results.add({
            'görev': task,
            'kurallı': verdict.toPlainText(),
            'yerel_yanıt': text,
            'belirteç': finished.tokenCount,
          });
        }
        final report = Platform.environment['ITIRAZ_REAL_REPORT'];
        if (report != null) {
          await File(report).writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'model': info.displayName,
              'dosya_bayt': imported.size,
              'mimari': info.architecture,
              'sonuçlar': results,
            }),
          );
        }
      } finally {
        await svc.dispose();
        dir.deleteSync(recursive: true);
      }
    },
    skip: model == null ? 'ITIRAZ_REAL_MODEL tanımlı değil' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
