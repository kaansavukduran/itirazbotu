/// "Kurallı değerlendirme": modelsiz, internetsiz, tamamen Dart ile çalışan karar motoru.
///
/// Motor, girişi Türkçe kurallarla katlar (bkz. `text_norm.dart`), ardından öncelik
/// sırasına dizilmiş kuralları dener. İlk eşleşen kural kararı ve metinleri verir;
/// gizlilik gibi değiştiriciler sonucu tamamlar. Hiçbir kural eşleşmezse kesin karar
/// uydurulmaz, bunun yerine tek bir açıklayıcı soru sorulur.
library;

import 'text_norm.dart';
import 'verdict.dart';

/// Kural motoru sürümü; kural kümesi değiştikçe artırılır.
const String ruleEngineVersion = '1.0.0';

/// Bir kalıp: varsayılan olarak kelime başından eşleşen kök ("ozur" → "özürlerimi").
/// "r:" ile başlarsa katlanmış metne uygulanan düzenli ifadedir.
class _Matcher {
  _Matcher(String pattern)
    : _stem = pattern.startsWith('r:') ? null : pattern,
      _re = pattern.startsWith('r:') ? RegExp(pattern.substring(2)) : null;

  final String? _stem;
  final RegExp? _re;

  bool matches(String folded) =>
      _re != null ? _re.hasMatch(folded) : containsStem(folded, _stem!);
}

class _Signal {
  _Signal(List<String> patterns) : _m = patterns.map(_Matcher.new).toList();
  final List<_Matcher> _m;
  bool any(String folded) => _m.any((m) => m.matches(folded));
}

/// Kullanılan sinyal grupları. Kalıplar katlanmış (aksansız, küçük harf) yazılır.
final Map<String, _Signal> _signals = {
  'meta': _Signal([
    'yapay zeka karsiti',
    'yapay zekaya karsi yapay zeka',
    'ai karsiti',
    'anti ai',
    'itiraz botu',
    'kendini sorgulayan yapay zeka',
    'yapay zeka kullanmayi sorgulayan',
  ]),
  'secret': _Signal([
    r'r:(^| )(sifre|parola)(?!le)',
    'pin kod',
    'pin numara',
    'kart numara',
    'kredi karti numara',
    'cvv',
    'tc kimlik',
    'kimlik numara',
    'iban',
    'dogrulama kod',
    'tek kullanimlik kod',
    'api anahtar',
    'api key',
    'gizli anahtar',
    'private key',
    'kurtarma kelime',
    'seed phrase',
  ]),
  'pii': _Signal([
    'adres',
    'telefon numara',
    'e posta adres',
    'saglik rapor',
    'tahlil',
    'kan degerleri',
    'maas',
    'bordro',
    'musteri bilgi',
    'musteri list',
    'kisisel veri',
    'kisisel bilgi',
    'ozel mesaj',
    'gunlugum',
    'sirrim',
  ]),
  'apology': _Signal([
    'ozur',
    'ozr',
    'af dile',
    'affet',
    'kusura bakma',
    'barisma',
    'gonlunu al',
    'gonlunu alma',
  ]),
  'condolence': _Signal([
    'taziye',
    'bassagligi',
    'vefat',
    'cenaze',
    'kaybi icin',
    'kaybindan dolayi',
  ]),
  'celebrate': _Signal([
    'tesekkur',
    'tebrik',
    'kutla',
    'dogum gunu',
    'yildonum',
    'mezuniyet mesaj',
    'bayram mesaj',
    'yeni yil mesaj',
  ]),
  'romance': _Signal([
    'sevgilim',
    'sevgilime',
    'sevgilimi',
    'sevgiliye',
    'ask mektub',
    r'r:(^| )ask(im|ima|imi|imin)( |$)',
    'ask ilan',
    'evlilik teklif',
    'seni seviyorum',
    'ayrilik mesaj',
    'flort',
    'hoslandigim',
  ]),
  'closePerson': _Signal([
    'arkadasima',
    'arkadasim',
    'anneme',
    'annem',
    'babama',
    'babam',
    'esime',
    'kardesime',
    'dedeme',
    'nineme',
    'anneanneme',
    'babaanneme',
    'teyzeme',
    'halama',
    'dayima',
    'amcama',
    'cocuguma',
    'kizima',
    'ogluma',
    'komsuma',
    'hocama',
    'ogretmenime',
  ]),
  'message': _Signal([
    'mesaj',
    'cevap yaz',
    'yanit yaz',
    'not yaz',
    'kart yaz',
    'mektup',
    'mektub',
    'whatsapp',
    'sms',
    'dm',
  ]),
  'speech': _Signal([
    'konusma metni',
    'dugun konusma',
    'veda konusma',
    'kadeh kaldir',
    'nikah konusma',
  ]),
  'medical': _Signal([
    r'r:(^| )saglik(?!li)',
    'ilac',
    r'r:(^| )doz(u|unu|lar|aj)?( |$)',
    'teshis',
    'tani koy',
    'belirti',
    'semptom',
    'hastalig',
    'hastalik',
    'tedavi',
    'recete',
    'agri',
    'ates',
    'tansiyon',
    'kan deger',
    'tahlil',
    'doktor',
    'hekim',
  ]),
  'legal': _Signal([
    'dava',
    'avukat',
    'hukuk',
    'sozlesme',
    'dilekce',
    'ihtarname',
    'mahkeme',
    'kanun',
    'yasa ',
    'icra',
    'bosanma',
    'miras',
    'vekaletname',
    'kira artis',
    'tahliye',
    'kvkk',
  ]),
  'money': _Signal([
    'yatirim',
    'hisse',
    'kripto',
    'borsa',
    'kredi',
    r'r:(^| )borc',
    'vergi',
    'sigorta',
    'emeklilik',
    'faiz',
    'doviz',
    'altin al',
    'bitcoin',
    'fon al',
    'portfoy',
  ]),
  'career': _Signal([
    'cv',
    'ozgecmis',
    'is basvuru',
    'on yazi',
    'motivasyon mektub',
    'niyet mektub',
    'mulakat',
    'istifa',
    'maas pazarlig',
    'terfi',
    'referans mektub',
  ]),
  'lifeDecision': _Signal([
    'karar veremiyorum',
    'karar ver',
    'ne yapmaliyim',
    'hangisini sec',
    'secmeli miyim',
    'ayrilayim mi',
    'ayrilsam mi',
    'tasinayim mi',
    'tasinsam mi',
    'bolum sec',
    'universite sec',
    'tercih yap',
    'evleneyim mi',
    'birakayim mi',
    'biraksam mi',
  ]),
  'homework': _Signal([
    'odev',
    'soruyu',
    'sorusunu',
    'sorulari',
    'sorusu',
    r'r:(^| )soru( |$)',
    r'r:(^| )coz',
    'test coz',
    'sinav',
    'matematik',
    'fizik',
    'kimya',
    'biyoloji',
    'geometri',
    'integral',
    'turev',
    'denklem',
    'yks',
    'lgs',
    'kpss',
    'alistirma',
    'quiz',
  ]),
  'essay': _Signal([
    'kompozisyon',
    'makale',
    'deneme yaz',
    r'r:(^| )tez(i|imi|imin|e|de|ler)?( |$)',
    'rapor yaz',
    'proje odev',
    'sunum hazirla',
    'essay',
    'odev metni',
  ]),
  'learnConcept': _Signal([
    r'r:(^| )ogren(?!ci)',
    'anlamak ist',
    'anlamiyorum',
    'konu anlat',
    'konusunu anlat',
    'ders cal',
    'ders not',
    'calismam',
    'ezber',
    'kelime calis',
    'dil ogren',
    'nasil calisir',
    r'r:(^| )nedir( |$)',
    'kursta',
    'kurs icin',
  ]),
  'creative': _Signal([
    'siir',
    'hikaye',
    'oyku',
    'sarki soz',
    r'r:(^| )roman(i|imi|imin|a|da)?( |$)',
    'senaryo',
    'beste',
    'masal',
    'resim ciz',
    'karikatur',
  ]),
  'ideas': _Signal([
    'fikir',
    'isim oner',
    'isim bul',
    'beyin firtina',
    'slogan',
    'baslik oner',
    'hediye',
    'ne pisirsem',
    'tarif oner',
  ]),
  'code': _Signal([
    r'r:(^| )kod(u|unu|lar|larini|da|unda|ları)?( |$)',
    'kod yaz',
    'betik',
    'script',
    'fonksiyon',
    'regex',
    'duzenli ifade',
    'sql',
    'sorgu yaz',
    'python',
    'javascript',
    'typescript',
    'dart',
    'flutter',
    'java',
    'c++',
    'c#',
    'excel formul',
    'formul yaz',
    'makro',
    'hata ayikla',
    'debug',
    r'r:(^| )bug(lar|i|u)?( |$)',
    'derleme hata',
    'api',
    'program yaz',
    'uygulama yaz',
    'site yap',
    'web sitesi',
  ]),
  'simplify': _Signal([
    'sadelestir',
    'basitlestir',
    'anlasilir hale',
    'anlasilir yap',
    'yalinlastir',
    'daha anlasilir',
  ]),
  'summary': _Signal([
    'ozetle',
    'ozet cikar',
    'ozetini',
    'kisalt',
    'toparla',
    'toplanti not',
  ]),
  'spelling': _Signal([
    'yazim hata',
    'imla',
    'noktalama',
    'dilbilgisi',
    'gramer',
    'typo',
    'duzelt',
    'redakte',
  ]),
  'translate': _Signal([
    'cevir',
    'tercume',
    'ingilizceye',
    'turkceye',
    'almancaya',
    'fransizcaya',
    'ispanyolcaya',
    'arapcaya',
    'rusca',
  ]),
  'format': _Signal([
    'bicimlendir',
    'formatla',
    'tabloya',
    'tablo haline',
    'listeye',
    'liste haline',
    'madde madde',
    'alfabetik',
    'sirala',
    'csv',
    'json',
    'donustur',
    'markdown',
  ]),
  'businessText': _Signal([
    'resmi e posta',
    'resmi mail',
    'is e posta',
    'is maili',
    'mail yaz',
    'e posta yaz',
    'eposta yaz',
    'toplanti davet',
    'duyuru yaz',
    'urun aciklama',
    'ilan metni',
  ]),
  // "Bu işi yapay zekâya yaptırayım mı?" gibi sarmalayıcı kelimeler.
  'wrapper': _Signal([
    'yapay zeka',
    'yapay zekaya',
    'chatgpt',
    'yaptirayim',
    'yaptirsam',
    'yaptirmali',
    'sorayim mi',
    'sorsam mi',
    'yazdirayim',
    'yazdirsam',
  ]),
};

const Set<String> _fillerWords = {
  'bu', 'su', 'o', 'isi', 'is', 'isini', 'yapay', 'zeka', 'zekaya', 'zekanin', 'ai',
  'chatgpt', 'llm', 'yaptirayim', 'yaptirsam', 'yaptirmali', 'miyim', 'mi', 'mu',
  'mı', 'sorayim', 'sorsam', 'yazdirayim', 'yazdirsam', 'bunu', 'sunu', 'sence',
  'acaba', 'ne', 'dersin', 'yap', 'yaz', 'et', 'bir', 'sey', 'ben', 'bana', 'lutfen',
  'yapar', 'misin', 'musun', 'yardim', 'eder', 'icin', 've', 'ile', 'de', 'da',
};

bool _has(String key, String folded) => _signals[key]!.any(folded);

/// Kurallı değerlendirme motoru. Durumsuzdur; aynı girişe her zaman aynı sonucu verir.
class RuleEngine {
  const RuleEngine();

  /// [input] metnini değerlendirir. [taskType] verilirse (kullanıcı görev türünü
  /// seçtiyse) eşleşme bulunamadığında o türün genel kuralı kullanılır.
  ///
  /// Boş girişte [EmptyInputException] fırlatır.
  Verdict evaluate(String input, {TaskType? taskType}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) throw const EmptyInputException();
    final f = foldTurkish(trimmed);
    if (f.isEmpty) {
      return const Verdict.clarify(
        question: 'Bunu harflerle bir cümle olarak yazar mısın? Ne yapmak istediğini anlamam lazım.',
      );
    }

    final verdict = _match(f) ?? (taskType != null ? _forType(taskType, f) : null);
    if (verdict != null) return _applyModifiers(verdict, f);

    final meaningful = f.split(' ').where((w) => w.length >= 2 && !_fillerWords.contains(w));
    if (meaningful.isEmpty && _has('wrapper', f)) {
      return const Verdict.clarify(
        question: 'Hangi iş? Yapmak istediğin şeyi bir cümleyle yazarsan ya da türünü seçersen netleştireyim.',
      );
    }
    if (_has('message', f)) {
      return const Verdict.clarify(
        question: 'Bu mesaj kime ve ne için? Türünü seçersen daha net söylerim.',
        options: [TaskType.personalMessage, TaskType.textEdit, TaskType.highStakes],
      );
    }
    return const Verdict.clarify(
      question: 'Bunu tam çıkaramadım. Hangi tür bir iş olduğunu seçer misin?',
    );
  }

  Verdict? _match(String f) {
    bool h(String k) => _has(k, f);

    // 1. Bu uygulamanın kendisine dair soru: önce model gerçekten gerekli mi?
    if (h('meta')) {
      return const Verdict(
        decision: Decision.selfDo,
        reason:
            'Önce neden bir modele ihtiyaç olduğunu sorgula. Tek işin "Bunu kendin yapabilir misin?" diye sormaksa, bir post-it de iş görür.',
        firstStep: 'Bir post-it\'e "Bunu kendin yapabilir misin?" yaz ve ekranının kenarına yapıştır.',
        supportLimit:
            'Model ancak kararın bağlama göre değiştiği yerde gerekir; o da cihazında, kapalı devre çalışsın.',
        factors: [Factor.meta],
        ruleId: 'meta',
      );
    }

    // 2. Gizli bilgi: parola, kimlik numarası, kart bilgisi.
    if (h('secret')) {
      return const Verdict(
        decision: Decision.selfDo,
        reason:
            'Bu iş gizli bir bilgi içeriyor. Bir kez yapıştırınca nereye gittiğini ve kimin göreceğini kontrol edemezsin.',
        firstStep:
            'Bilgiyi hiçbir sohbete yazmadan, cihazındaki parola yöneticisinde veya resmi uygulamada kendin hallet.',
        supportLimit:
            'Yapay zekâya yalnızca genel yöntemi sorabilirsin ("güçlü parola nasıl seçilir?"); gerçek değeri asla yazma.',
        factors: [Factor.privacy],
        ruleId: 'secret',
      );
    }

    final personal = h('apology') || h('condolence') || h('celebrate') || h('romance') ||
        h('speech') || (h('closePerson') && h('message'));

    // 3. Kişisel metnin yalnızca mekanik düzeltmesi.
    if (personal && (h('spelling') || h('format'))) {
      return const Verdict(
        decision: Decision.limited,
        reason:
            'Sözler senin, düzeltme mekanik. Yapay zekâ cümlelerini değiştirirse mesaj senin olmaktan çıkar.',
        firstStep: 'Mesajı bir kez sesli oku; takıldığın yerleri önce kendin düzelt.',
        supportLimit: 'Yalnızca yazım ve noktalama hatalarını işaretlemesini iste, yeniden yazdırma.',
        factors: [Factor.personal, Factor.routine],
        ruleId: 'personal-edit',
      );
    }

    // 4. Kişisel ifade.
    if (h('condolence')) {
      return const Verdict(
        decision: Decision.selfDo,
        reason:
            'Taziyede kusursuz cümle aranmaz. Kısa ve senden çıktığı belli olan bir mesaj, hazır bir metinden daha iyi gelir.',
        firstStep:
            'Kaybedilen kişiyle ilgili bir anını ya da "yanındayım" demenin somut bir yolunu tek cümleyle yaz.',
        factors: [Factor.personal],
        ruleId: 'condolence',
      );
    }
    if (h('apology')) {
      return const Verdict(
        decision: Decision.selfDo,
        reason:
            'Özrün değeri, neye üzüldüğünü senin sözlerinle duymaktan gelir. Hazır cümleler bunu taşıyamaz.',
        firstStep:
            'Neye üzüldüğünü ve telafi için ne yapacağını kendi sözlerinle, iki üç cümleyle yaz.',
        supportLimit:
            'İstersen yazdığını okutup yalnızca suçlayıcı kaçan bir ifade olup olmadığını sorabilirsin.',
        factors: [Factor.personal],
        ruleId: 'apology',
      );
    }
    if (h('romance')) {
      return const Verdict(
        decision: Decision.selfDo,
        reason:
            'Romantik mesajda karşı taraf seni duymak ister. Yapay zekâ cümlesi fark edilirse tatlı jest bir anda tuhaflaşır.',
        firstStep: 'Onda ilk kez fark ettiğin ve hâlâ sevdiğin bir şeyi süslemeden tek cümleyle yaz.',
        supportLimit: 'Yapay zekâ en fazla yazdığını okuyup anlaşılır olup olmadığını söyleyebilir.',
        factors: [Factor.personal],
        ruleId: 'romance',
      );
    }
    if (h('celebrate')) {
      return const Verdict(
        decision: Decision.selfDo,
        reason:
            'Kutlama ya da teşekkür mesajını özel yapan, ikinizin ortak bir anısı. Onu yalnızca sen biliyorsun.',
        firstStep: 'Ortak bir anıyı ya da sana iyi gelen bir davranışını tek cümleyle yaz, sonuna içten bir dilek ekle.',
        supportLimit: 'Takılırsan yalnızca tek bir kelime ya da kapanış önerisi iste; gövde senden çıksın.',
        factors: [Factor.personal],
        ruleId: 'celebrate',
      );
    }
    if (h('speech')) {
      return const Verdict(
        decision: Decision.selfDo,
        reason: 'Bu konuşmayı dinleyenler seni tanıyor; ezber kalıplar yerine senin anıların akılda kalır.',
        firstStep: 'Anlatmak istediğin tek bir anıyı ve sonunda söyleyeceğin dileği not et.',
        supportLimit: 'Akış önerisi (giriş, anı, dilek) isteyebilirsin; anılar ve cümleler senden.',
        factors: [Factor.personal],
        ruleId: 'speech',
      );
    }
    if (personal) {
      return const Verdict(
        decision: Decision.selfDo,
        reason:
            'Yakın birine giden mesajda tonunu en iyi sen bilirsin; karşı taraf da seni tanıdığı için farkı hemen anlar.',
        firstStep: 'Söylemek istediğini önce sesli söyle, sonra aynen tek paragraf olarak yaz.',
        supportLimit: 'Uzun olduysa yalnızca kısaltma önerisi iste.',
        factors: [Factor.personal],
        ruleId: 'close-message',
      );
    }

    // 5. Sonuçları ağır işler.
    if (h('medical')) {
      return const Verdict(
        decision: Decision.limited,
        reason:
            'Sağlıkta yanlış bir ayrıntının bedeli yüksek ve yapay zekâ seni muayene edemez. Sağlık bilgilerin de hassas veridir.',
        firstStep:
            'Belirtilerini, ne zaman başladığını ve kullandığın ilaçları bir nota yaz; bunu hekim veya eczacıyla paylaş.',
        supportLimit:
            'Yapay zekâdan yalnızca hekime soracağın soruları derlemesini ya da bir terimi açıklamasını iste; tanı ve doz kararı ona bırakılmaz.',
        factors: [Factor.stakes, Factor.privacy],
        ruleId: 'medical',
      );
    }
    if (h('legal')) {
      return const Verdict(
        decision: Decision.limited,
        reason:
            'Hukuki metinde tek kelime sonucu değiştirebilir. Yapay zekâ güncel mevzuatı ve senin dosyanın ayrıntılarını bilmeyebilir.',
        firstStep: 'Olayları tarih sırasıyla ve elindeki belgelerle birlikte madde madde yaz.',
        supportLimit:
            'Metni anlaşılır kılmak için yardım alabilirsin; son hâlini bir avukatla veya resmi kaynakla kontrol et.',
        factors: [Factor.stakes, Factor.privacy],
        ruleId: 'legal',
      );
    }
    if (h('money')) {
      return const Verdict(
        decision: Decision.limited,
        reason:
            'Para kararının sonucunu sen yaşarsın. Model senin risk durumunu ve bugünkü piyasayı tam bilemez.',
        firstStep: 'Gelirini, giderini ve hedefini üç satırda yaz; ne kadar kaybı kaldırabileceğini belirle.',
        supportLimit:
            'Yapay zekâdan faiz, enflasyon gibi kavramları açıklamasını iste; al, sat ya da başvur kararını ona bırakma.',
        factors: [Factor.stakes],
        ruleId: 'money',
      );
    }
    if (h('career')) {
      return const Verdict(
        decision: Decision.limited,
        reason:
            'Başvuru metni seni temsil eder. İşverenler birbirine benzeyen hazır cümleleri hızla fark eder.',
        firstStep: 'Son işinde ya da okulunda çözdüğün somut bir sorunu ve sonucunu iki cümleyle yaz.',
        supportLimit:
            'Yazdığın metnin yazım ve düzen kontrolünü yaptırabilirsin; deneyim ya da beceri uydurtma.',
        factors: [Factor.stakes, Factor.personal],
        ruleId: 'career',
      );
    }
    if (h('lifeDecision')) {
      return const Verdict(
        decision: Decision.selfDo,
        reason:
            'Bu kararın sonucunu sen yaşayacaksın ve neye değer verdiğini en iyi sen biliyorsun.',
        firstStep:
            'İki seçeneği yan yana yaz; her biri için "bir yıl sonra neyi kaybetmiş olurum?" sorusunu yanıtla.',
        supportLimit: 'Yapay zekâ yalnızca gözden kaçırdığın soruları sorabilir; seçimi o yapmaz.',
        factors: [Factor.stakes, Factor.personal],
        ruleId: 'life-decision',
      );
    }

    // 6. Öğrenme.
    if (h('code') && (h('homework') || h('learnConcept'))) {
      return const Verdict(
        decision: Decision.limited,
        reason: 'Kodlamayı öğrenirken hatayla boğuşmak işin kendisi; hazır kod o kası çalıştırmaz.',
        firstStep: 'Hata mesajını oku, hatanın olduğu satırı bul ve o satırdan ne beklediğini yaz.',
        supportLimit: 'Yalnızca hata mesajının ne anlama geldiğini sor; düzeltilmiş kodu isteme.',
        factors: [Factor.learning],
        ruleId: 'code-learning',
      );
    }
    if (h('summary') && (h('homework') || h('learnConcept') || h('essay'))) {
      return const Verdict(
        decision: Decision.limited,
        reason: 'Ders notunu özetlemek öğrenmenin yarısı; özeti başkası çıkarırsa o yarıyı atlamış olursun.',
        firstStep: 'Her başlığın altına, bakmadan hatırladığın tek cümleyi yaz.',
        supportLimit: 'Kendi özetin bittikten sonra yapay zekânın özetiyle karşılaştır, eksikleri ekle.',
        factors: [Factor.learning],
        ruleId: 'study-summary',
      );
    }
    if (h('essay')) {
      return const Verdict(
        decision: Decision.limited,
        reason:
            'Ödev metni senin düşünme sürecini ölçer. Yapay zekâ yazarsa hem öğrenme hem akademik dürüstlük riske girer.',
        firstStep: 'Ana fikrini tek cümle, destekleyen üç noktanı madde madde yaz.',
        supportLimit:
            'Taslağın bittikten sonra yalnızca akış ve yazım geri bildirimi iste; kurumunun yapay zekâ kuralına da bak.',
        factors: [Factor.learning, Factor.personal],
        ruleId: 'essay',
      );
    }
    if (h('homework')) {
      return const Verdict(
        decision: Decision.limited,
        reason:
            'Bu soruyu çözmek, sonra gelecek benzerlerini çözebilmek demek. Hazır çözüm sınavda yanında olmaz.',
        firstStep: 'Önce kendi adımını dene: verilenleri ve isteneni ayrı ayrı yaz, ilk işlemi yap.',
        supportLimit:
            'Takıldığın adımda yalnızca bir ipucu iste; tam çözümü kendi denemenle karşılaştırmak için kullan.',
        factors: [Factor.learning],
        ruleId: 'homework',
      );
    }
    if (h('learnConcept')) {
      return const Verdict(
        decision: Decision.limited,
        reason:
            'Bir konuyu dinlemek onu öğrenmek demek değil; kendin hatırlamaya çalıştığında kalıcı olur.',
        firstStep: 'Konu hakkında bildiklerini kitabı kapatıp beş dakika yaz, boş kalan yerleri işaretle.',
        supportLimit: 'Yapay zekâdan yalnızca işaretlediğin boşluğu açıklamasını ya da seni sınamasını iste.',
        factors: [Factor.learning],
        ruleId: 'learn',
      );
    }

    // 7. Yaratıcı işler.
    if (h('creative')) {
      return const Verdict(
        decision: Decision.limited,
        reason:
            'Yaratıcı işin keyfi ve sesi sende. Yapay zekâ ortalamanın ortalamasını yazar; senin tuhaf ayrıntını bilmez.',
        firstStep: 'On dakikalık sayaç kur ve hiç düzeltmeden ilk taslağı yaz.',
        supportLimit: 'Tıkandığında tek bir kafiye ya da tek bir fikir iste; metni ona yazdırma.',
        factors: [Factor.creativity, Factor.personal],
        ruleId: 'creative',
      );
    }
    if (h('ideas')) {
      return const Verdict(
        decision: Decision.delegate,
        reason: 'Fikir listesi çıkarmak düşük riskli ve hızlı; en iyisini seçmek yine senin işin.',
        firstStep: 'Önce aklına gelen üç fikri yaz; listeyi bunlarla kıyaslarsın.',
        supportLimit: 'Fikir listesini yaptırabilirsin; seçimi ve son dokunuşu kendin yap.',
        factors: [Factor.creativity, Factor.routine],
        ruleId: 'ideas',
      );
    }

    // 8. Teknik ve mekanik işler.
    if (h('code')) {
      return const Verdict(
        decision: Decision.delegate,
        reason: 'Tekrarlanan teknik işi yapay zekâ hızlandırır ve doğruluğu çalıştırınca görülür.',
        firstStep: 'Girdi ve beklenen çıktıya bir örnek yaz; sonucu bununla test edeceksin.',
        supportLimit: 'Kodu yazdırabilirsin; anlamadan ve test etmeden kullanma.',
        factors: [Factor.routine],
        ruleId: 'code',
      );
    }
    if (h('simplify')) {
      return const Verdict(
        decision: Decision.delegate,
        reason: 'Sadeleştirme, anlamı koruyup biçimi değiştiren mekanik bir iş; yapay zekâ burada iyidir.',
        firstStep: 'Metnin ana fikrini tek cümleyle not et; sadeleşmiş hâl bu cümleyle uyuşmalı.',
        supportLimit: 'Sadeleştirmeyi yaptırabilirsin; metnin anlamını son okumada kendin kontrol et.',
        factors: [Factor.routine],
        ruleId: 'simplify',
      );
    }
    if (h('summary')) {
      return const Verdict(
        decision: Decision.delegate,
        reason: 'Uzun bir metni kısaltmak zaman alan ama mekanik bir iş.',
        firstStep: 'Metinde senin için en önemli üç noktayı önceden yaz; özet bunları içermeli.',
        supportLimit: 'Özeti yaptırabilirsin; isim, rakam ve tarihleri asıl metinle karşılaştır.',
        factors: [Factor.routine],
        ruleId: 'summary',
      );
    }
    if (h('spelling')) {
      return const Verdict(
        decision: Decision.delegate,
        reason: 'Yazım düzeltmesi kurala dayalı ve kolay denetlenen bir iş.',
        firstStep: 'Metni bir kez sesli oku; gözünden kaçanı kulağın yakalar.',
        supportLimit: 'Düzeltmeleri yaptırabilirsin; değişiklikleri tek tek görüp onayla.',
        factors: [Factor.routine],
        ruleId: 'spelling',
      );
    }
    if (h('translate')) {
      return const Verdict(
        decision: Decision.delegate,
        reason: 'Gündelik çeviri için yapay zekâ hızlı ve çoğu zaman yeterli.',
        firstStep: 'Metnin kime gideceğini ve resmi mi samimi mi olacağını not et.',
        supportLimit: 'Çeviriyi yaptırabilirsin; resmi ya da önemli bir metni bir bilene kontrol ettir.',
        factors: [Factor.routine],
        ruleId: 'translate',
      );
    }
    if (h('format')) {
      return const Verdict(
        decision: Decision.delegate,
        reason: 'Biçim dönüştürmek tekrar eden ve sonucu kolay görülen bir iş.',
        firstStep: 'İstediğin biçimden iki satırlık bir örnek hazırla.',
        supportLimit: 'Dönüştürmeyi yaptırabilirsin; satır sayısının ve verilerin eksiksiz olduğunu kontrol et.',
        factors: [Factor.routine],
        ruleId: 'format',
      );
    }
    if (h('businessText')) {
      return const Verdict(
        decision: Decision.delegate,
        reason: 'Rutin iş yazışması kalıplara dayanır; taslağı hızla çıkarabilir.',
        firstStep: 'Ana mesajı, tarihi ve karşı taraftan istediğin eylemi üç madde olarak yaz.',
        supportLimit: 'Taslağı yaptırabilirsin; isimleri, tarihleri ve tonu göndermeden kontrol et.',
        factors: [Factor.routine],
        ruleId: 'business-text',
      );
    }
    return null;
  }

  /// Kullanıcı görev türünü seçtiğinde, eşleşme yoksa o türün genel kararı.
  Verdict _forType(TaskType type, String f) {
    switch (type) {
      case TaskType.personalMessage:
        return const Verdict(
          decision: Decision.selfDo,
          reason: 'Kişisel mesajda değer, senin sesinden gelir; hazır metin bunu taşıyamaz.',
          firstStep: 'Ne hissettiğini ve karşı taraftan ne beklediğini iki cümleyle yaz.',
          supportLimit: 'Yalnızca yazdığının anlaşılır olup olmadığını sorabilirsin.',
          factors: [Factor.personal],
          ruleId: 'type-personal',
        );
      case TaskType.learning:
        return const Verdict(
          decision: Decision.limited,
          reason: 'Öğrenme, kendin denediğinde gerçekleşir; hazır cevap yalnızca bugünü kurtarır.',
          firstStep: 'İlk adımı kendin dene ve nerede takıldığını tek cümleyle yaz.',
          supportLimit: 'Takıldığın yer için yalnızca bir ipucu iste.',
          factors: [Factor.learning],
          ruleId: 'type-learning',
        );
      case TaskType.textEdit:
        return const Verdict(
          decision: Decision.delegate,
          reason: 'Metni düzenlemek çoğu zaman mekanik bir iş ve sonucu kolay denetlenir.',
          firstStep: 'Metnin ana fikrini tek cümleyle not et.',
          supportLimit: 'Düzenlemeyi yaptırabilirsin; anlamın değişmediğini son okumada kontrol et.',
          factors: [Factor.routine],
          ruleId: 'type-text',
        );
      case TaskType.code:
        return const Verdict(
          decision: Decision.delegate,
          reason: 'Teknik işin doğruluğu çalıştırınca görülür; yapay zekâ taslağı hızlandırır.',
          firstStep: 'Girdi ve beklenen çıktıya bir örnek yaz.',
          supportLimit: 'Kodu yazdırabilirsin; anlamadan ve test etmeden kullanma.',
          factors: [Factor.routine],
          ruleId: 'type-code',
        );
      case TaskType.highStakes:
        return const Verdict(
          decision: Decision.limited,
          reason: 'Sonucu ağır bir işte son sözü bir modele bırakmak riskli; sorumluluk sende kalır.',
          firstStep: 'Durumu, seçenekleri ve son tarihleri madde madde yaz.',
          supportLimit:
              'Kavramları açıklatabilir ya da soru listesi çıkartabilirsin; kararı ve son kontrolü kendin ya da bir uzman yapsın.',
          factors: [Factor.stakes],
          ruleId: 'type-stakes',
        );
      case TaskType.creative:
        return const Verdict(
          decision: Decision.limited,
          reason: 'Yaratıcı işte ses senin; yapay zekâ ancak tıkandığında kıvılcım olur.',
          firstStep: 'On dakika boyunca düzeltmeden ilk taslağı yaz.',
          supportLimit: 'Tek bir fikir ya da kelime önerisi iste; işi ona yazdırma.',
          factors: [Factor.creativity],
          ruleId: 'type-creative',
        );
    }
  }

  /// Gizlilik gibi ikincil etkenleri sonuca ekler.
  Verdict _applyModifiers(Verdict v, String f) {
    if (!_has('pii', f) || v.factors.contains(Factor.privacy)) return v;
    const note = 'Paylaşmadan önce isim, adres ve numara gibi kişisel bilgileri çıkar.';
    return Verdict(
      decision: v.decision!,
      reason: v.reason,
      firstStep: v.firstStep,
      supportLimit: v.supportLimit == null ? note : '${v.supportLimit} $note',
      factors: [...v.factors, Factor.privacy],
      ruleId: '${v.ruleId}+pii',
    );
  }
}
