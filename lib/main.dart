import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Paketlenen Inter yazı tipinin lisansı (OFL-1.1) "Lisanslar" sayfasında görünsün.
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/INTER_LICENSE.txt');
    yield LicenseEntryWithLineBreaks(['Inter yazı tipi'], text);
  });

  final controller = await createController(await getApplicationSupportDirectory());
  runApp(ItirazApp(controller: controller));
}
