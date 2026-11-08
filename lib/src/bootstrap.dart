import 'dart:io';

import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'data/app_state.dart';
import 'llm/local_model_service.dart';
import 'llm/model_store.dart';

/// Uygulama durumunu verilen destek dizininde kurar (testlerde geçici dizin verilir).
Future<AppController> createController(Directory support, {AssetLoader? assetLoader}) async {
  final sep = Platform.pathSeparator;
  final models = LocalModelService();
  final settings = AppSettings(File('${support.path}${sep}settings.json'));
  final history = HistoryStore(File('${support.path}${sep}history.json'));
  await settings.load();
  if (settings.historyEnabled) {
    await history.load();
  } else {
    // Geçmiş kapalıyken eski bir dosya kalmasın.
    await history.clear();
  }
  final controller = AppController(
    settings: settings,
    history: history,
    models: models,
    store: ModelStore(Directory('${support.path}${sep}models'), freeDiskOf: models.freeDisk),
    assetLoader: assetLoader ?? rootBundle.load,
  );
  await controller.init();
  return controller;
}
