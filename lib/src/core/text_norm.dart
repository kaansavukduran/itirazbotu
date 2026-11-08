/// Türkçe metin normalleştirme yardımcıları.
///
/// Kural motoru eşleşmeyi "katlanmış" metin üzerinde yapar: Türkçe kurallara göre
/// küçük harfe çevrilir (I→ı, İ→i), ardından aksanlar sadeleştirilir (ç→c, ğ→g,
/// ı→i, ö→o, ş→s, ü→u, â→a). Böylece "Özür", "ÖZÜR", "ozur" aynı şekilde eşleşir.
library;

/// Türkçe kurallarla küçük harfe çevirir. Dart'ın `toLowerCase` işlevi "I" harfini
/// "i" yapar; Türkçede doğrusu "ı"dır.
String turkishLower(String input) {
  final sb = StringBuffer();
  for (final rune in input.runes) {
    switch (rune) {
      case 0x0049: // I
        sb.write('ı');
      case 0x0130: // İ
        sb.write('i');
      default:
        sb.write(String.fromCharCode(rune).toLowerCase());
    }
  }
  // "i̇" (i + birleşik nokta) gibi kalıntıları temizle.
  return sb.toString().replaceAll('̇', '');
}

const Map<String, String> _fold = {
  'ç': 'c',
  'ğ': 'g',
  'ı': 'i',
  'ö': 'o',
  'ş': 's',
  'ü': 'u',
  'â': 'a',
  'î': 'i',
  'û': 'u',
  'é': 'e',
  'è': 'e',
  'ä': 'a',
};

/// Küçük harfe çevirip aksanları sadeleştirir, noktalama işaretlerini boşluğa
/// dönüştürür ve fazla boşlukları siler.
String foldTurkish(String input) {
  final lower = turkishLower(input);
  final sb = StringBuffer();
  for (final ch in lower.split('')) {
    final f = _fold[ch];
    if (f != null) {
      sb.write(f);
    } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
      sb.write(ch);
    } else if (ch == '+' || ch == '#') {
      sb.write(ch); // "c++", "c#" gibi ifadeler korunur.
    } else {
      sb.write(' ');
    }
  }
  return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Katlanmış metinde, bir kelimenin başından başlayan [stem] ifadesini arar.
/// Türkçe sondan eklemeli olduğu için kelime sonu sınırı aranmaz:
/// "ozur" kalıbı "ozurlerimi" kelimesini de yakalar.
bool containsStem(String folded, String stem) {
  if (stem.isEmpty) return false;
  var start = 0;
  while (true) {
    final i = folded.indexOf(stem, start);
    if (i < 0) return false;
    if (i == 0 || folded.codeUnitAt(i - 1) == 0x20) return true;
    start = i + 1;
  }
}

/// Anlamlı kelime sayısı (2 harften kısa parçalar sayılmaz).
int wordCount(String folded) =>
    folded.split(' ').where((w) => w.length >= 2).length;
