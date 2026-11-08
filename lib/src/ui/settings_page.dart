import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/rule_engine.dart';
import '../llm/gguf_inspector.dart';
import '../llm/local_model_service.dart';
import '../llm/model_store.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.c});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListenableBuilder(
        listenable: Listenable.merge([c, c.settings]),
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _header(context, 'Görünüm'),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('Sistem'), icon: Icon(Icons.brightness_auto)),
                      ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode_outlined)),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode_outlined)),
                    ],
                    selected: {c.settings.themeMode},
                    onSelectionChanged: (s) => c.settings.update(theme: s.first),
                  ),
                ),
                SwitchListTile(
                  key: const Key('large-text'),
                  title: const Text('Büyük yazı'),
                  subtitle: const Text('Tüm metinleri yaklaşık üçte bir büyütür.'),
                  value: c.settings.largeText,
                  onChanged: (v) => c.settings.update(large: v),
                ),
                const Divider(),
                _header(context, 'Gizlilik'),
                SwitchListTile(
                  key: const Key('history-switch'),
                  title: const Text('Geçmişi tut'),
                  subtitle: const Text('Varsayılan olarak kapalı. Açarsan kayıtlar yalnızca bu cihazda tutulur; kapatınca silinir.'),
                  value: c.settings.historyEnabled,
                  onChanged: c.setHistoryEnabled,
                ),
                ListTile(
                  title: Text('${c.history.entries.length} kayıt'),
                  trailing: OutlinedButton.icon(
                    key: const Key('clear-history'),
                    onPressed: c.history.entries.isEmpty
                        ? null
                        : () async {
                            await c.clearHistory();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geçmiş temizlendi.')));
                            }
                          },
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Geçmişi temizle'),
                  ),
                ),
                const Divider(),
                _header(context, 'Yerel model (isteğe bağlı)'),
                Text(
                  'Uygulama modelsiz de tam çalışır. Bir GGUF model dosyası eklersen, sonuç ekranındaki '
                  '"Yerel modelle ayrıntılandır" düğmesi cihazında, internetsiz çalışır.',
                  style: t.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                ModelSection(c: c),
                const Divider(),
                _header(context, 'Hakkında'),
                const ListTile(
                  leading: Icon(Icons.wifi_off),
                  title: Text('Tamamen çevrimdışı'),
                  subtitle: Text('Hesap, telemetri, reklam ya da uzaktan güncelleme yok. Uygulama ağ isteği yapmaz.'),
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Sürümler'),
                  subtitle: const Text('Uygulama 1.0.0 · Kural motoru $ruleEngineVersion · llama.cpp b11900'),
                  onTap: () => showLicensePage(context: context, applicationName: 'İtiraz Botu', applicationVersion: '1.0.0'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String s) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Semantics(header: true, child: Text(s, style: Theme.of(context).textTheme.titleMedium)),
      );
}

class ModelSection extends StatelessWidget {
  const ModelSection({super.key, required this.c});
  final AppController c;

  Future<void> _pick(BuildContext context) async {
    try {
      final f = await FilePicker.pickFile(dialogTitle: 'GGUF model dosyası seç', type: FileType.any);
      final path = f?.path;
      if (path == null) return;
      await c.importModel(path);
    } catch (e) {
      c.modelMessage = 'Dosya seçici açılamadı. "Yolu elle gir" ile dosyanın yerini yazabilirsiniz.';
      await c.refreshModels();
    }
  }

  /// Masaüstünde dosya seçici (ör. Linux'ta XDG portalı) yoksa yolu elle girme.
  Future<void> _enterPath(BuildContext context) async {
    final ctrl = TextEditingController();
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Model dosyasının yolu'),
        content: TextField(
          key: const Key('path-field'),
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '/home/kullanici/Modeller/model.gguf'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('İçe aktar')),
        ],
      ),
    );
    ctrl.dispose();
    if (path != null && path.trim().isNotEmpty) await c.importModel(path.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final svc = c.models;
    final desktop = Platform.isLinux || Platform.isWindows || Platform.isMacOS;
    if (!svc.isSupported) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.block, color: t.colorScheme.error),
          title: const Text('Yerel model bu kurulumda kullanılamıyor'),
          subtitle: Text('${svc.unsupportedReason ?? ''} Kurallı değerlendirme çalışmaya devam eder.'),
        ),
      );
    }
    final loading = svc.state == ModelState.loading;
    final busy = loading || c.isImporting || svc.state == ModelState.generating;
    final b = c.bundled;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        liveRegion: true,
        child: Card(
          color: t.colorScheme.surfaceContainerHighest,
          child: ListTile(
            leading: Icon(svc.isLoaded ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                color: svc.isLoaded ? Colors.green.shade700 : null),
            title: Text(
              switch (svc.state) {
                ModelState.ready => 'Durum: Hazır · ${svc.loadedName}',
                ModelState.generating => 'Durum: Yanıt üretiyor · ${svc.loadedName}',
                ModelState.loading => 'Durum: Yükleniyor…',
                ModelState.error => 'Durum: Hata',
                _ => 'Durum: Model yüklü değil',
              },
              key: const Key('model-status'),
            ),
            subtitle: Text(c.deviceSummary()),
          ),
        ),
      ),
      if (loading) ...[
        LinearProgressIndicator(value: c.modelLoadProgress),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: c.cancelModelLoad, child: const Text('Yüklemeyi iptal et')),
        ),
      ],
      if (c.isImporting) ...[
        const SizedBox(height: 8),
        Text('${c.importLabel ?? ''} · %${((c.importProgress ?? 0) * 100).toStringAsFixed(0)}'),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: c.importProgress, semanticsLabel: 'İçe aktarma ilerlemesi'),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(key: const Key('cancel-import'), onPressed: c.cancelImport, child: const Text('İptal')),
        ),
      ],
      if (c.modelMessage != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(c.modelMessage!, key: const Key('model-message'), style: t.textTheme.bodyMedium),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          key: const Key('import-model'),
          onPressed: busy ? null : () => _pick(context),
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Dosyadan model ekle (.gguf)'),
        ),
        if (desktop)
          TextButton(
            key: const Key('enter-path'),
            onPressed: busy ? null : () => _enterPath(context),
            child: const Text('Yolu elle gir'),
          ),
        if (b != null && c.store.preparedBundled(b) == null)
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final m = await c.prepareBundledModel();
                    if (m != null) await c.loadModel(m);
                  },
            icon: const Icon(Icons.inventory_2_outlined),
            label: Text('Paketteki modeli kullan (${b.displayName ?? b.fileName})'),
          ),
        if (svc.isLoaded)
          OutlinedButton.icon(onPressed: busy ? null : c.unloadModel, icon: const Icon(Icons.eject), label: const Text('Bellekten çıkar')),
      ]),
      const SizedBox(height: 12),
      if (c.storedModels.isEmpty)
        Text('Cihazda kayıtlı model yok.', style: t.textTheme.bodyMedium)
      else
        for (final m in c.storedModels) _modelTile(context, m, busy),
      const SizedBox(height: 8),
      Text(
        'İpucu: 4–8 GB bellekli cihazlar için 0,5–1,5 milyar parametreli, Q4_K_M nicemlemeli '
        'Türkçe destekli bir model (ör. Qwen2.5 Instruct, Apache-2.0) uygundur.',
        style: t.textTheme.bodySmall,
      ),
    ]);
  }

  Widget _modelTile(BuildContext context, StoredModel m, bool busy) {
    final loaded = c.models.loadedPath == m.path;
    return Card(
      child: ListTile(
        leading: Icon(m.bundled ? Icons.inventory_2_outlined : Icons.description_outlined),
        title: Text(m.fileName),
        subtitle: Text('${formatBytes(m.size)}${m.bundled ? ' · paketle geldi' : ''}${loaded ? ' · yüklü' : ''}'),
        trailing: Wrap(spacing: 4, children: [
          if (!loaded)
            TextButton(onPressed: busy ? null : () => c.loadModel(m), child: const Text('Yükle')),
          IconButton(
            tooltip: '${m.fileName} dosyasını sil',
            icon: const Icon(Icons.delete_outline),
            onPressed: busy
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Model silinsin mi?'),
                        content: Text('${m.fileName} (${formatBytes(m.size)}) cihazdan silinecek.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil')),
                        ],
                      ),
                    );
                    if (ok == true) await c.deleteModel(m);
                  },
          ),
        ]),
      ),
    );
  }
}
