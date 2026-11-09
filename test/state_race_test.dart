import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:itiraz_botu/src/app_controller.dart';
import 'package:itiraz_botu/src/data/app_state.dart';
import 'package:itiraz_botu/src/llm/local_model_service.dart';
import 'package:itiraz_botu/src/llm/model_store.dart';

class ControlledModel extends LocalModelService {
  final events = StreamController<GenerationEvent>.broadcast();
  final updates = StreamController<ModelState>.broadcast();
  ModelState current = ModelState.ready;
  int stops = 0;

  @override
  ModelState get state => current;
  @override
  Stream<ModelState> get states => updates.stream;
  @override
  Stream<GenerationEvent> generate({
    required String system,
    required String user,
    int maxTokens = 320,
    double temperature = 0.4,
    int? seed,
  }) {
    current = ModelState.generating;
    return events.stream;
  }

  @override
  void stop() => stops++;
  @override
  Future<void> dispose() async {
    await events.close();
    await updates.close();
    await super.dispose();
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('itiraz_race_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('bekleyen geçmiş yazımları temizlemeden sonra dosyayı geri getirmez', () async {
    final file = File('${dir.path}/new/history.json');
    final history = HistoryStore(file);
    final writes = List.generate(
      20,
      (i) => history.add(
        HistoryEntry(time: DateTime.now(), input: 'görev $i', outcome: 'karar', mode: 'kurallı'),
        enabled: true,
      ),
    );
    final cleared = history.clear();
    await Future.wait([...writes, cleared]);
    expect(history.entries, isEmpty);
    expect(file.existsSync(), isFalse);
  });

  test('hızlı ayar değişikliklerinde geçmişin son kapalı tercihi diskte korunur', () async {
    final file = File('${dir.path}/settings.json');
    final settings = AppSettings(file);
    final on = settings.update(history: true);
    final off = settings.update(history: false);
    await Future.wait([on, off]);
    final restored = AppSettings(file);
    await restored.load();
    expect(restored.historyEnabled, isFalse);
  });

  test('yeni görev eski üretim olaylarını ve geçmiş kaydını yok sayar', () async {
    final model = ControlledModel();
    final settings = AppSettings(File('${dir.path}/settings.json'));
    final history = HistoryStore(File('${dir.path}/history.json'));
    final controller = AppController(
      settings: settings,
      history: history,
      models: model,
      store: ModelStore(Directory('${dir.path}/models'), freeDiskOf: (_) => -1),
      assetLoader: (_) async => throw StateError('modelsiz'),
    );
    controller.evaluate('Arkadaşıma özür mesajı yaz.');
    controller.refine();
    model.events.add(GenerationChunk('Eski yanıt'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.refineText, 'Eski yanıt');
    controller.evaluate('Bu paragrafı sadeleştir.');
    model.events.add(GenerationChunk(' geç gelen parça'));
    model.events.add(GenerationFinished(cancelled: true));
    await Future<void>.delayed(Duration.zero);
    expect(model.stops, 1);
    expect(controller.refineText, isEmpty);
    expect(controller.refineStatus, RefineStatus.none);
    expect(controller.lastInput, 'Bu paragrafı sadeleştir.');
    controller.dispose();
    // Kapatma sırasında gelen durum değişikliği artık dinlenmez.
    model.updates.add(ModelState.empty);
    await Future<void>.delayed(Duration.zero);
  });
}
