import 'package:flutter/material.dart';

import '../app_controller.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.c});
  final AppController c;

  String _fmt(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Geçmiş'),
        actions: [
          ListenableBuilder(
            listenable: c.history,
            builder: (_, _) => TextButton.icon(
              onPressed: c.history.entries.isEmpty ? null : c.clearHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Temizle'),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: c.history,
        builder: (context, _) {
          final e = c.history.entries;
          if (e.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Kayıt yok. Geçmiş yalnızca bu cihazda tutulur.')));
          }
          return ListView.separated(
            itemCount: e.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => ListTile(
              title: Text(e[i].input, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${e[i].outcome} · ${e[i].mode} · ${_fmt(e[i].time)}'),
            ),
          );
        },
      ),
    );
  }
}
