import 'package:flutter_test/flutter_test.dart';
import 'package:itiraz_botu/src/llm/prompt.dart';

void main() {
  test('sohbet şablonu ve düşünme artıkları kullanıcı yanıtından temizlenir', () {
    expect(cleanModelOutput('<think>iç düşünce</think>Önce kendi cümleni yaz.<|im_end|>'), 'Önce kendi cümleni yaz.');
  });

  test('istem tekrarı başarılı ayrıntı olarak işaretlenmez', () {
    expect(isPromptEcho('Görev: "Arkadaşıma özür mesajı yaz."'), isTrue);
    expect(isPromptEcho('Kurallı değerlendirme:\nKarar: Kendin yap'), isTrue);
    expect(isPromptEcho('Neye üzüldüğünü bir cümleyle yaz; sesin duyulsun.'), isFalse);
  });
}
