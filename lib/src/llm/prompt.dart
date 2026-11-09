/// Yerel model için istem metinleri.
library;

import '../core/verdict.dart';

const String refineSystemPrompt =
    'Sen İtiraz Botu\'sun: insanların bir işi yapay zekâya devretmeden önce kendileri '
    'yapıp yapamayacaklarını düşünmelerine yardım eden, kısa, samimi, hafif esprili ve '
    'yargılamayan bir asistansın. Yalnızca Türkçe yaz. Verilen kararı değiştirme; onu bu '
    'işe özel ayrıntılandır. En fazla dört kısa cümle yaz: önce bu işe özel nedeni, sonra '
    'hemen denenebilecek somut bir adımı, en son yapay zekânın yardım edebileceği en küçük '
    'parçayı söyle. Başlık, liste ya da emoji kullanma. Kişisel bilgi isteme.';

String buildRefinePrompt(String task, Verdict v) =>
    'Görev: "$task"\n\n'
    'Kurallı değerlendirme:\n${v.toPlainText()}\n\n'
    'Bu değerlendirmeyi bu göreve özel olarak ayrıntılandır.';

/// Küçük modellerin bazen eklediği şablon kalıntılarını temizler.
String cleanModelOutput(String s) {
  var t = s;
  for (final tag in ['<|im_end|>', '<|eot_id|>', '<end_of_turn>', '</s>', '<|end|>', '<|endoftext|>']) {
    t = t.replaceAll(tag, '');
  }
  t = t.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
  return t.trim();
}

/// Küçük modeller bazen açıklama üretmek yerine girdiyi kopyalar. Bunu başarılı
/// bir ayrıntı gibi sunmayalım; kurallı kart her durumda kullanılabilir kalır.
bool isPromptEcho(String text) =>
    text.trimLeft().startsWith('Görev:') ||
    text.contains('Kurallı değerlendirme:') ||
    (text.contains('Karar:') && text.contains('Gerekçe:'));
