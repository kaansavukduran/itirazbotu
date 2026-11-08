import 'package:flutter_test/flutter_test.dart';
import 'package:itiraz_botu/src/core/rule_engine.dart';
import 'package:itiraz_botu/src/core/text_norm.dart';
import 'package:itiraz_botu/src/core/verdict.dart';

void main() {
  const engine = RuleEngine();

  Verdict ev(String s, {TaskType? type}) => engine.evaluate(s, taskType: type);

  group('Türkçe normalleştirme', () {
    test('I/İ Türkçe kurala göre küçülür', () {
      expect(turkishLower('IŞIK İZMİR'), 'ışık izmir');
    });
    test('aksanlar katlanır, noktalama boşluğa döner', () {
      expect(foldTurkish('Özür dilerim, ÇOK üzgünüm!'), 'ozur dilerim cok uzgunum');
      expect(foldTurkish('Yapay zekâ'), 'yapay zeka');
    });
    test('kök eşleşmesi kelime başından yapılır', () {
      expect(containsStem('ozurlerimi kabul et', 'ozur'), isTrue);
      expect(containsStem('kozur', 'ozur'), isFalse);
    });
  });

  group('Örnek senaryolar', () {
    test('özür mesajı → Kendin yap', () {
      final v = ev('Arkadaşıma özür mesajı yaz.');
      expect(v.decision, Decision.selfDo);
      expect(v.ruleId, 'apology');
      expect(v.firstStep, contains('kendi sözlerinle'));
      expect(v.factors, contains(Factor.personal));
    });
    test('matematik sorusu → Sınırlı destek', () {
      final v = ev('Bu matematik sorusunu çöz.');
      expect(v.decision, Decision.limited);
      expect(v.ruleId, 'homework');
      expect(v.firstStep, contains('kendi adımını'));
      expect(v.supportLimit, contains('ipucu'));
    });
    test('paragraf sadeleştirme → Devredebilirsin', () {
      final v = ev('Bu paragrafı sadeleştir.');
      expect(v.decision, Decision.delegate);
      expect(v.supportLimit, contains('anlamını son okumada kendin kontrol et'));
    });
    test('yapay zekâ karşıtı yapay zekâ → post-it', () {
      final v = ev('Yapay zekâ karşıtı yapay zekâ yap.');
      expect(v.ruleId, 'meta');
      expect(v.reason, contains('post-it'));
    });
  });

  group('Türkçe karakter dayanıklılığı', () {
    for (final s in [
      'ARKADAŞIMA ÖZÜR MESAJI YAZ',
      'arkadasima ozur mesaji yaz',
      'Arkadaşıma özrümü ilet',
      'ARKADAŞIMDAN ÖZÜR DİLEMEK İSTİYORUM',
    ]) {
      test('"$s" → özür', () => expect(ev(s).ruleId, 'apology'));
    }
    test('büyük İ ve I içeren giriş', () {
      expect(ev('İNTEGRAL SORUSUNU ÇÖZ').decision, Decision.limited);
      expect(ev('BU METNİ İNGİLİZCEYE ÇEVİR').ruleId, 'translate');
    });
  });

  group('Gerekçeyi etkileyen etkenler', () {
    test('parola → gizlilik, Kendin yap', () {
      final v = ev('E-posta şifremi hatırlamama yardım et');
      expect(v.decision, Decision.selfDo);
      expect(v.factors, [Factor.privacy]);
    });
    test('şifreleme kodu parola sayılmaz', () {
      expect(ev('Python ile şifreleme fonksiyonu yaz').ruleId, 'code');
    });
    test('kişisel veri içeren rutin iş → gizlilik notu', () {
      final v = ev('Müşteri listesindeki adresleri tabloya dök');
      expect(v.decision, Decision.delegate);
      expect(v.factors, contains(Factor.privacy));
      expect(v.supportLimit, contains('kişisel bilgileri çıkar'));
    });
    test('sağlık → Sınırlı destek, uzmana yönlendirme', () {
      final v = ev('Bu ilacın dozunu ne kadar artırmalıyım?');
      expect(v.decision, Decision.limited);
      expect(v.factors, containsAll([Factor.stakes, Factor.privacy]));
      expect(v.firstStep, contains('hekim'));
    });
    test('hukuk metni sadeleştirme yine de sınırlı', () {
      expect(ev('Kira sözleşmemi sadeleştir').ruleId, 'legal');
    });
    test('kişisel mesajın yazım düzeltmesi → sınırlı', () {
      final v = ev('Özür mesajımdaki yazım hatalarını düzelt');
      expect(v.decision, Decision.limited);
      expect(v.ruleId, 'personal-edit');
    });
    test('ödev özeti öğrenme kuralına düşer', () {
      expect(ev('Ders notlarımı özetle').ruleId, 'study-summary');
    });
    test('kod ödevi → öğrenme', () {
      expect(ev('Python ödevimdeki kodu yaz').ruleId, 'code-learning');
    });
    test('bugün kelimesi "bug" sayılmaz', () {
      expect(ev('Bugün toplantı notlarını özetle').ruleId, 'summary');
    });
    test('öğrenci kelimesi öğrenme sayılmaz', () {
      expect(ev('Öğrencilere resmi e-posta yaz').ruleId, 'business-text');
    });
    test('hayat kararı → Kendin yap', () {
      expect(ev('İstanbul\'a taşınayım mı karar veremiyorum').decision, Decision.selfDo);
    });
  });

  group('Belirsiz ve hatalı girişler', () {
    test('boş giriş hata verir', () {
      expect(() => ev(''), throwsA(isA<EmptyInputException>()));
      expect(() => ev('   \n\t'), throwsA(isA<EmptyInputException>()));
    });
    test('yalnızca noktalama → soru', () {
      expect(ev('?!...').needsClarification, isTrue);
    });
    test('bilinmeyen görev → kesin karar yerine soru ve tür seçimi', () {
      final v = ev('Şu işi bir halletsen');
      expect(v.needsClarification, isTrue);
      expect(v.decision, isNull);
      expect(v.options, TaskType.values);
    });
    test('yalnızca sarmalayıcı soru → hangi iş?', () {
      final v = ev('Bu işi yapay zekâya yaptırayım mı?');
      expect(v.needsClarification, isTrue);
      expect(v.clarifyQuestion, startsWith('Hangi iş?'));
    });
    test('sarmalayıcıyla gelen görev değerlendirilir', () {
      expect(ev('Bu paragrafı sadeleştirmeyi yapay zekâya yaptırayım mı?').decision,
          Decision.delegate);
    });
    test('kime olduğu belirsiz mesaj → daraltılmış seçenekler', () {
      final v = ev('Bir mesaj yaz');
      expect(v.needsClarification, isTrue);
      expect(v.options, contains(TaskType.personalMessage));
    });
    test('tür seçimi kararı belirler', () {
      expect(ev('Şu işi bir halletsen', type: TaskType.learning).decision, Decision.limited);
      expect(ev('Şu işi bir halletsen', type: TaskType.personalMessage).decision,
          Decision.selfDo);
      expect(ev('Şu işi bir halletsen', type: TaskType.textEdit).decision, Decision.delegate);
    });
    test('çok uzun giriş çökmez', () {
      final long = 'Bu paragrafı sadeleştir. ${'çok uzun metin ' * 5000}';
      expect(ev(long).decision, Decision.delegate);
    });
    test('emoji ve diğer alfabeler', () {
      expect(ev('🙏 annemin doğum günü mesajı').ruleId, 'celebrate');
      expect(ev('日本語のテキスト').needsClarification, isTrue);
    });
  });

  test('her karar dolu gerekçe ve ilk adım içerir', () {
    for (final t in TaskType.values) {
      final v = ev('xyz', type: t);
      expect(v.reason, isNotEmpty);
      expect(v.firstStep, isNotEmpty);
      expect(v.toPlainText(), contains('Karar:'));
    }
  });
}
