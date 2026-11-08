import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

class ItirazApp extends StatelessWidget {
  const ItirazApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.settings,
      builder: (context, _) => MaterialApp(
        title: 'İtiraz Botu',
        debugShowCheckedModeBanner: false,
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: controller.settings.themeMode,
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final factor = controller.settings.largeText ? 1.3 : 1.0;
          return MediaQuery(
            data: mq.copyWith(textScaler: _ScaledTextScaler(mq.textScaler, factor)),
            child: child!,
          );
        },
        home: HomePage(c: controller),
      ),
    );
  }
}

/// Sistem yazı boyutunun üstüne uygulama içi büyütme ekler.
class _ScaledTextScaler extends TextScaler {
  const _ScaledTextScaler(this.base, this.factor);
  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.scale(14) / 14 * factor;

  @override
  bool operator ==(Object other) => other is _ScaledTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
