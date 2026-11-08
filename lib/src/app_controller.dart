/// Uygulamanın tek durum kaynağı: giriş, kurallı sonuç, yerel model ayrıntısı,
/// model yönetimi, ayarlar ve geçmiş.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'core/rule_engine.dart';
import 'core/verdict.dart';
import 'data/app_state.dart';
import 'llm/gguf_inspector.dart';
import 'llm/local_model_service.dart';
import 'llm/model_store.dart';
import 'llm/prompt.dart';

/// Yerel model ayrıntısının durumu.
enum RefineStatus { none, running, done, cancelled, failed }

class AppController extends ChangeNotifier {
  AppController({
    required this.settings,
    required this.history,
    required this.models,
    required this.store,
    required this.assetLoader,
    this.engine = const RuleEngine(),
  }) {
    models.states.listen((_) => notifyListeners());
  }

  final RuleEngine engine;
  final AppSettings settings;
  final HistoryStore history;
  final LocalModelService models;
  final ModelStore store;
  final AssetLoader assetLoader;

  // --- Değerlendirme ---
  String lastInput = '';
  Verdict? verdict;
  String? inputError;

  // --- Yerel model ayrıntısı ---
  RefineStatus refineStatus = RefineStatus.none;
  String refineText = '';
  String? refineError;
  String? refineModelName;
  StreamSubscription<GenerationEvent>? _refineSub;

  // --- Model yönetimi ---
  List<StoredModel> storedModels = [];
  BundledModelManifest? bundled;
  double? modelLoadProgress;
  String? modelMessage;
  double? importProgress;
  String? importLabel;
  CancelToken? _importCancel;

  bool get isImporting => importProgress != null;

  Future<void> init() async {
    bundled = await ModelStore.readManifest(assetLoader);
    await refreshModels();
  }

  /// Kurallı değerlendirme. Ağ ve model gerektirmez, anında döner.
  void evaluate(String input, {TaskType? type}) {
    stopRefine();
    refineStatus = RefineStatus.none;
    refineText = '';
    refineError = null;
    try {
      final v = engine.evaluate(input, taskType: type);
      verdict = v;
      lastInput = input.trim();
      inputError = null;
      unawaited(history.add(
        HistoryEntry(
          time: DateTime.now(),
          input: lastInput,
          outcome: v.needsClarification ? 'Soru soruldu' : v.decision!.label,
          mode: 'Kurallı değerlendirme',
        ),
        enabled: settings.historyEnabled,
      ));
    } on EmptyInputException catch (e) {
      verdict = null;
      inputError = e.message;
    }
    notifyListeners();
  }

  void clearResult() {
    stopRefine();
    verdict = null;
    inputError = null;
    refineStatus = RefineStatus.none;
    refineText = '';
    notifyListeners();
  }

  bool get canRefine =>
      verdict != null && !verdict!.needsClarification && models.state == ModelState.ready;

  /// Yalnızca kullanıcı "Yerel modelle ayrıntılandır" dediğinde çalışır.
  void refine() {
    final v = verdict;
    if (v == null || v.needsClarification) return;
    if (models.state != ModelState.ready) {
      refineStatus = RefineStatus.failed;
      refineError = 'Yerel model yüklü değil. Kurallı sonuç geçerliliğini koruyor.';
      notifyListeners();
      return;
    }
    refineStatus = RefineStatus.running;
    refineText = '';
    refineError = null;
    refineModelName = models.loadedName;
    notifyListeners();
    _refineSub = models
        .generate(system: refineSystemPrompt, user: buildRefinePrompt(lastInput, v))
        .listen((e) {
      switch (e) {
        case GenerationChunk(:final text):
          refineText += text;
        case GenerationFinished(:final cancelled, :final error):
          refineText = cleanModelOutput(refineText);
          if (error != null) {
            refineStatus = RefineStatus.failed;
            refineError = '$error Kurallı sonuç geçerliliğini koruyor.';
          } else if (cancelled) {
            refineStatus = RefineStatus.cancelled;
          } else if (refineText.trim().isEmpty) {
            refineStatus = RefineStatus.failed;
            refineError = 'Model boş yanıt döndürdü. Kurallı sonuç geçerliliğini koruyor.';
          } else {
            refineStatus = RefineStatus.done;
            unawaited(history.add(
              HistoryEntry(
                time: DateTime.now(),
                input: lastInput,
                outcome: '${v.decision!.label} + ayrıntı',
                mode: 'Yerel model · ${refineModelName ?? ''}',
              ),
              enabled: settings.historyEnabled,
            ));
          }
      }
      notifyListeners();
    });
  }

  void stopRefine() {
    if (refineStatus == RefineStatus.running) models.stop();
  }

  // --- Model yönetimi ---

  Future<void> refreshModels() async {
    storedModels = await store.list();
    notifyListeners();
  }

  /// Ayarlarda etkin işaretli modeli yükler (uygulama açılışında otomatik değil).
  Future<void> loadModel(StoredModel m) async {
    modelMessage = null;
    modelLoadProgress = 0;
    notifyListeners();
    try {
      await models.load(m.path,
          displayName: _nameFor(m), onProgress: (p) {
            modelLoadProgress = p;
            notifyListeners();
          });
      await settings.update(model: m.path);
      modelMessage = 'Model hazır: ${_nameFor(m)}';
    } on ModelLoadException catch (e) {
      modelMessage = e.cancelled ? 'Model yüklemesi iptal edildi.' : e.message;
    } finally {
      modelLoadProgress = null;
      notifyListeners();
    }
  }

  void cancelModelLoad() => models.cancelLoad();

  Future<void> unloadModel() async {
    await models.unload();
    modelMessage = 'Model bellekten çıkarıldı.';
    notifyListeners();
  }

  Future<void> deleteModel(StoredModel m) async {
    if (models.loadedPath == m.path) await models.unload();
    await store.delete(m);
    if (settings.activeModelPath == m.path) await settings.update(clearModel: true);
    modelMessage = '${m.fileName} silindi.';
    await refreshModels();
  }

  String _nameFor(StoredModel m) {
    if (m.bundled && bundled?.displayName != null) return bundled!.displayName!;
    return m.fileName;
  }

  /// Seçilen yerel dosyayı içe aktarır; ilerleme ve iptal desteklidir.
  Future<StoredModel?> importModel(String path) async {
    _importCancel = CancelToken();
    importProgress = 0;
    importLabel = 'Dosya denetleniyor…';
    modelMessage = null;
    notifyListeners();
    try {
      final info = await inspectGgufFile(path);
      importLabel = 'Kopyalanıyor: ${info.displayName}';
      notifyListeners();
      final m = await store.importFile(path, cancel: _importCancel, onProgress: _throttledProgress);
      modelMessage = info.warnings.isEmpty
          ? 'İçe aktarıldı: ${m.fileName}'
          : 'İçe aktarıldı: ${m.fileName}. Not: ${info.warnings.join(' ')}';
      await refreshModels();
      return m;
    } on GgufException catch (e) {
      modelMessage = e.message;
    } on ImportCancelled catch (e) {
      modelMessage = e.message;
    } on ImportFailure catch (e) {
      modelMessage = e.message;
    } finally {
      importProgress = null;
      importLabel = null;
      _importCancel = null;
      notifyListeners();
    }
    return null;
  }

  /// "Model dâhil" paketteki modeli hazırlar (ilk kullanımda bir kez, ağ yok).
  Future<StoredModel?> prepareBundledModel() async {
    final b = bundled;
    if (b == null) return null;
    final ready = store.preparedBundled(b);
    if (ready != null) return ready;
    _importCancel = CancelToken();
    importProgress = 0;
    importLabel = 'Paketteki model hazırlanıyor';
    notifyListeners();
    try {
      final m = await store.prepareBundled(b, assetLoader, cancel: _importCancel, onProgress: _throttledProgress);
      await refreshModels();
      return m;
    } on ImportCancelled catch (e) {
      modelMessage = e.message;
    } on ImportFailure catch (e) {
      modelMessage = e.message;
    } finally {
      importProgress = null;
      importLabel = null;
      _importCancel = null;
      notifyListeners();
    }
    return null;
  }

  void cancelImport() => _importCancel?.cancel();

  /// İlerlemeyi en fazla yüzde birlik adımlarla bildir (arayüzü yormasın).
  void _throttledProgress(int done, int total) {
    final p = total == 0 ? 0.0 : done / total;
    if (importProgress == null || p >= 1 || p - importProgress! >= 0.01) {
      importProgress = p;
      notifyListeners();
    }
  }

  // --- Ayarlar ve geçmiş ---

  Future<void> setHistoryEnabled(bool on) async {
    await settings.update(history: on);
    if (!on) await history.clear();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await history.clear();
    notifyListeners();
  }

  String deviceSummary() {
    final ram = models.availableRam();
    final disk = models.freeDisk(store.dir.existsSync() ? store.dir.path : store.dir.parent.path);
    return 'Boş bellek: ${formatBytes(ram)} · Boş alan: ${formatBytes(disk)} · '
        '${Platform.numberOfProcessors} işlemci çekirdeği';
  }

  @override
  void dispose() {
    _refineSub?.cancel();
    unawaited(models.dispose());
    super.dispose();
  }
}
