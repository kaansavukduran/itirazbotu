import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itiraz_botu/src/app.dart';
import 'package:itiraz_botu/src/app_controller.dart';
import 'package:itiraz_botu/src/bootstrap.dart';

void main() {
  late Directory tmp;
  late AppController c;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('itiraz_ui');
      c = await createController(tmp, assetLoader: (k) async => throw FlutterError('yok: $k'));
    });
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ItirazApp(controller: c));
    await tester.pumpAndSettle();
  }

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('ilk ekran: giriş, Değerlendir ve üç örnek', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('input')), findsOneWidget);
    expect(find.text('Değerlendir'), findsOneWidget);
    expect(find.byType(ActionChip), findsNWidgets(3));
    expect(find.byKey(const Key('decision')), findsNothing);
  });

  testWidgets('boş giriş yardımcı hata gösterir', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('evaluate')));
    await tester.pumpAndSettle();
    expect(find.text('Önce yapmak istediğin işi bir cümleyle yaz.'), findsOneWidget);
    expect(find.byKey(const Key('decision')), findsNothing);
  });

  testWidgets('örneğe dokununca karar, gerekçe, ilk adım ve mod görünür', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Arkadaşıma özür mesajı yaz.'));
    await tester.pumpAndSettle();
    expect(find.text('Kendin yap'), findsOneWidget);
    expect(find.text('Gerekçe'), findsOneWidget);
    expect(find.text('Yapay zekâsız yol'), findsOneWidget);
    expect(find.text('Destek sınırı'), findsOneWidget);
    expect(find.text('Kurallı değerlendirme'), findsOneWidget);
    expect(find.text('Kişisel ifade'), findsOneWidget);
    // Model yoksa ayrıntılandırma devre dışı ve nedeni yazılı.
    expect(find.textContaining('Ayarlar\'dan cihazındaki bir modeli'), findsOneWidget);
  });

  testWidgets('ekran okuyucu kararı etiketle duyurur', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    await tester.tap(find.text('Bu paragrafı sadeleştir.'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Karar: Yapay zekâya devredebilirsin'), findsOneWidget);
    expect(find.bySemanticsLabel('Kullanılan mod: Kurallı değerlendirme'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('Ctrl+Enter ile değerlendirme, Türkçe karakterler', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('input')), 'İNTEGRAL SORUSUNU ÇÖZ');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Sınırlı destek al'), findsOneWidget);
  });

  testWidgets('bilinmeyen görev soru sorar, tür seçimi karar verir', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byKey(const Key('input')), 'Şu işi bir halletsen');
    await tester.tap(find.byKey(const Key('evaluate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clarify')), findsOneWidget);
    expect(find.byKey(const Key('decision')), findsNothing);
    await tester.tap(find.text('Ödev veya öğrenme'));
    await tester.pumpAndSettle();
    expect(find.text('Sınırlı destek al'), findsOneWidget);
  });

  testWidgets('geçmiş varsayılan kapalı; açılınca tutulur, tek dokunuşla silinir', (tester) async {
    await pumpApp(tester);
    final file = File('${tmp.path}/history.json');
    await tester.tap(find.text('Bu matematik sorusunu çöz.'));
    await tester.pumpAndSettle();
    expect(c.history.entries, isEmpty);
    expect(file.existsSync(), isFalse);
    expect(find.byTooltip('Geçmiş'), findsNothing);

    await tester.tap(find.byTooltip('Ayarlar (Ctrl+,)'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => c.setHistoryEnabled(true));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byKey(const Key('history-switch'))).value, isTrue);
    Navigator.of(tester.element(find.text('Ayarlar'))).pop();
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      c.evaluate('Bu paragrafı sadeleştir.');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(c.history.entries.single.outcome, 'Yapay zekâya devredebilirsin');
    expect(file.existsSync(), isTrue);
    expect(find.byTooltip('Geçmiş'), findsOneWidget);

    await tester.tap(find.byTooltip('Ayarlar (Ctrl+,)'));
    await tester.pumpAndSettle();
    expect(find.text('1 kayıt'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('clear-history')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(c.history.entries, isEmpty);
    expect(file.existsSync(), isFalse);
    expect(find.text('0 kayıt'), findsOneWidget);
  });

  testWidgets('büyük yazı ve koyu tema', (tester) async {
    await pumpApp(tester);
    final before = tester.getSize(find.text('Değerlendir')).height;
    await tester.runAsync(() => c.settings.update(large: true, theme: ThemeMode.dark));
    await tester.pumpAndSettle();
    final after = tester.getSize(find.text('Değerlendir')).height;
    expect(after, greaterThan(before * 1.2));
    expect(Theme.of(tester.element(find.text('Değerlendir'))).brightness, Brightness.dark);
  });

  testWidgets('dar telefonda büyük yazıyla karar ve ayarlar taşmaz', (tester) async {
    await pumpApp(tester);
    tester.view.physicalSize = const Size(320, 844);
    await tester.runAsync(() => c.settings.update(large: true));
    for (final task in ['Arkadaşıma özür mesajı yaz.', 'Bu paragrafı sadeleştir.', 'Şu işi hallet']) {
      c.evaluate(task);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byTooltip('Ayarlar (Ctrl+,)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('dokunma alanları en az 48 piksel', (tester) async {
    await pumpApp(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('model kütüphanesi yoksa ayarlar bunu açıkça söyler', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Ayarlar (Ctrl+,)'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Yerel model (isteğe bağlı)'), 200,
        scrollable: find.byType(Scrollable).last);
    if (!c.models.isSupported) {
      expect(find.text('Yerel model bu kurulumda kullanılamıyor'), findsOneWidget);
      expect(find.textContaining('Kurallı değerlendirme çalışmaya devam eder'), findsOneWidget);
    }
  });
}
