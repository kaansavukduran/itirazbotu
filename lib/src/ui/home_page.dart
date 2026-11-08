import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../core/verdict.dart';
import '../llm/local_model_service.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'theme.dart';

/// Dokunulabilir hazır örnekler (pakette, ağ gerektirmez).
const List<String> sampleTasks = [
  'Arkadaşıma özür mesajı yaz.',
  'Bu matematik sorusunu çöz.',
  'Bu paragrafı sadeleştir.',
];

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.c});
  final AppController c;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _resultKey = GlobalKey();

  AppController get c => widget.c;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _evaluate({TaskType? type}) {
    c.evaluate(_input.text, type: type);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _resultKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.1);
    });
  }

  void _useSample(String s) {
    _input.text = s;
    _input.selection = TextSelection.collapsed(offset: s.length);
    _evaluate();
  }

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsPage(c: c)));

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): c.stopRefine,
        const SingleActivator(LogicalKeyboardKey.comma, control: true): _openSettings,
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('İtiraz Botu'),
          actions: [
            ListenableBuilder(
              listenable: c.settings,
              builder: (_, _) => c.settings.historyEnabled
                  ? IconButton(
                      tooltip: 'Geçmiş',
                      icon: const Icon(Icons.history),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryPage(c: c))),
                    )
                  : const SizedBox.shrink(),
            ),
            IconButton(tooltip: 'Ayarlar (Ctrl+,)', icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
          ],
        ),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(
                      'Bir işi yapay zekâya yaptırmadan önce sor: kendin mi, biraz destekle mi, yoksa devret mi?',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    _inputField(context),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('evaluate'),
                      onPressed: _evaluate,
                      icon: const Icon(Icons.gavel_outlined),
                      label: const Text('Değerlendir'),
                    ),
                    const SizedBox(height: 4),
                    Text('Kısayol: Ctrl+Enter', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Semantics(header: true, child: Text('Örnekler', style: Theme.of(context).textTheme.titleSmall)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in sampleTasks)
                          ActionChip(
                            label: Text(s),
                            tooltip: 'Örneği değerlendir: $s',
                            onPressed: () => _useSample(s),
                            materialTapTargetSize: MaterialTapTargetSize.padded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    KeyedSubtree(key: _resultKey, child: _result(context)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputField(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _evaluate,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _evaluate,
      },
      child: TextField(
        key: const Key('input'),
        controller: _input,
        focusNode: _focus,
        autofocus: true,
        minLines: 4,
        maxLines: 10,
        maxLength: 4000,
        textInputAction: TextInputAction.newline,
        keyboardType: TextInputType.multiline,
        style: Theme.of(context).textTheme.titleMedium,
        decoration: InputDecoration(
          labelText: 'Ne yapmak istiyorsun?',
          hintText: 'Örn. "Bu işi yapay zekâya yaptırayım mı: sunum notlarımı özetlemek"',
          alignLabelWithHint: true,
          errorText: c.inputError,
        ),
      ),
    );
  }

  Widget _result(BuildContext context) {
    final v = c.verdict;
    if (v == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      container: true,
      child: v.needsClarification ? _clarify(context, v) : _verdictCard(context, v),
    );
  }

  Widget _modeBadge(BuildContext context, {required bool local, String? model}) {
    final t = Theme.of(context);
    final label = local ? 'Yerel model${model != null ? ' · $model' : ''}' : 'Kurallı değerlendirme';
    return Semantics(
      container: true,
      label: 'Kullanılan mod: $label',
      excludeSemantics: true,
      child: Row(children: [
        Icon(local ? Icons.memory : Icons.rule, size: 18, color: t.colorScheme.primary),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary))),
      ]),
    );
  }

  Widget _clarify(BuildContext context, Verdict v) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _modeBadge(context, local: false),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.help_outline, color: t.colorScheme.tertiary),
            const SizedBox(width: 8),
            Text('Bir şey soracağım', style: t.textTheme.titleMedium),
          ]),
          const SizedBox(height: 8),
          Text(v.clarifyQuestion!, key: const Key('clarify'), style: t.textTheme.bodyLarge),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in v.options)
              OutlinedButton(
                onPressed: () => _evaluate(type: o),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.label),
                  Text(o.hint, style: t.textTheme.bodySmall),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String body, IconData icon) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Semantics(
        container: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 20, color: t.colorScheme.secondary)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              SelectableText(body, style: t.textTheme.bodyLarge),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _verdictCard(BuildContext context, Verdict v) {
    final t = Theme.of(context);
    final st = DecisionStyle.of(v.decision!, t.brightness);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: st.color,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Semantics(
              container: true,
              header: true,
              label: 'Karar: ${v.decision!.label}',
              excludeSemantics: true,
              child: Row(children: [
                Icon(st.icon, color: st.onColor, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('KARAR', style: t.textTheme.labelSmall?.copyWith(color: st.onColor, letterSpacing: 1.2)),
                    Text(v.decision!.label,
                        key: const Key('decision'),
                        style: t.textTheme.headlineSmall?.copyWith(color: st.onColor, fontWeight: FontWeight.w700)),
                    Text(st.tagline, style: t.textTheme.bodyMedium?.copyWith(color: st.onColor)),
                  ]),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 10),
              _modeBadge(context, local: false),
              _section(context, 'Gerekçe', v.reason, Icons.lightbulb_outline),
              _section(context, 'Yapay zekâsız yol', v.firstStep, Icons.directions_walk),
              if (v.supportLimit != null) _section(context, 'Destek sınırı', v.supportLimit!, Icons.straighten),
              if (v.factors.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Text('Etkileyen:', style: t.textTheme.labelLarge),
                  for (final f in v.factors)
                    Chip(label: Text(f.label), visualDensity: VisualDensity.compact),
                ]),
              ],
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      _refinePanel(context, v),
    ]);
  }

  Widget _refinePanel(BuildContext context, Verdict v) {
    final t = Theme.of(context);
    final state = c.models.state;
    final status = c.refineStatus;

    if (status == RefineStatus.none) {
      if (state == ModelState.ready) {
        return OutlinedButton.icon(
          key: const Key('refine'),
          onPressed: c.refine,
          icon: const Icon(Icons.memory),
          label: Text('Yerel modelle ayrıntılandır · ${c.models.loadedName ?? ''}'),
        );
      }
      return Card(
        color: t.colorScheme.surfaceContainerHighest,
        child: ListTile(
          leading: const Icon(Icons.memory_outlined),
          title: const Text('Yerel modelle ayrıntılandır'),
          subtitle: Text(state == ModelState.loading
              ? 'Model yükleniyor…'
              : 'Bu sonuç kurallı değerlendirmeyle üretildi. İstersen Ayarlar\'dan cihazındaki bir modeli ekleyip yükleyebilirsin.'),
          trailing: TextButton(onPressed: _openSettings, child: const Text('Ayarlar')),
        ),
      );
    }

    final running = status == RefineStatus.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _modeBadge(context, local: true, model: c.refineModelName),
          const SizedBox(height: 4),
          Text(
            switch (status) {
              RefineStatus.running => 'Üretiliyor… (Esc ile durdur)',
              RefineStatus.done => 'Yerel model ayrıntısı',
              RefineStatus.cancelled => 'Durduruldu. Kurallı sonuç yukarıda geçerli.',
              RefineStatus.failed => 'Ayrıntı üretilemedi',
              RefineStatus.none => '',
            },
            key: const Key('refine-status'),
            style: t.textTheme.titleSmall,
          ),
          if (running) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
          if (c.refineText.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(c.refineText, key: const Key('refine-text'), style: t.textTheme.bodyLarge),
          ],
          if (c.refineError != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.error_outline, color: t.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(child: Text(c.refineError!, style: TextStyle(color: t.colorScheme.error))),
            ]),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            if (running)
              FilledButton.tonalIcon(
                key: const Key('stop'),
                onPressed: c.stopRefine,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Durdur'),
              )
            else if (state == ModelState.ready)
              OutlinedButton.icon(onPressed: c.refine, icon: const Icon(Icons.refresh), label: const Text('Yeniden üret')),
          ]),
          if (status == RefineStatus.done)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Model yanılabilir; karar ve son kontrol sende.', style: t.textTheme.bodySmall),
            ),
        ]),
      ),
    );
  }
}
