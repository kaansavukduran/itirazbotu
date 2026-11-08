/// Değerlendirme sonucunun veri modelleri.
library;

/// Botun üç olası kararı.
enum Decision {
  selfDo('Kendin yap'),
  limited('Sınırlı destek al'),
  delegate('Yapay zekâya devredebilirsin');

  const Decision(this.label);

  /// Ekranda ve ekran okuyucuda gösterilen Türkçe etiket.
  final String label;
}

/// Gerekçeyi etkileyen etkenler. Arayüzde yazıyla gösterilir.
enum Factor {
  personal('Kişisel ifade'),
  learning('Öğrenme'),
  privacy('Gizlilik'),
  stakes('Kararın sonuçları'),
  routine('Rutin, mekanik iş'),
  creativity('Yaratıcılık'),
  meta('Model gerçekten gerekli mi?');

  const Factor(this.label);
  final String label;
}

/// Kullanıcının bağlam yetersiz olduğunda seçebileceği görev türleri.
enum TaskType {
  personalMessage('Kişisel mesaj', 'Özür, teşekkür, tebrik, taziye…'),
  learning('Ödev veya öğrenme', 'Soru çözme, ödev, sınava hazırlık'),
  textEdit('Metin düzenleme', 'Sadeleştirme, özet, yazım düzeltme'),
  code('Kod veya teknik iş', 'Betik, hata ayıklama, dönüştürme'),
  highStakes('Önemli karar', 'Sağlık, hukuk, para, iş'),
  creative('Yaratıcı iş', 'Şiir, hikâye, tasarım fikri');

  const TaskType(this.label, this.hint);
  final String label;
  final String hint;
}

/// Kural motorunun ürettiği sonuç. Ya bir karar ya da bir açıklayıcı soru içerir.
class Verdict {
  const Verdict({
    required this.decision,
    required this.reason,
    required this.firstStep,
    this.supportLimit,
    this.factors = const [],
    this.ruleId = '',
  }) : clarifyQuestion = null,
       options = const [];

  const Verdict.clarify({required String question, this.options = TaskType.values})
    : decision = null,
      reason = '',
      firstStep = '',
      supportLimit = null,
      factors = const [],
      ruleId = 'clarify',
      clarifyQuestion = question;

  /// Karar; açıklayıcı soru sorulduğunda `null`.
  final Decision? decision;

  /// Bu iş özelinde bir iki cümlelik gerekçe.
  final String reason;

  /// Yapay zekâsız, hemen denenebilecek somut adım.
  final String firstStep;

  /// Uygunsa yapay zekânın yardımcı olabileceği en küçük parça.
  final String? supportLimit;

  /// Kararı etkileyen etkenler.
  final List<Factor> factors;

  /// Hangi kuralın tetiklendiği (test ve hata ayıklama için).
  final String ruleId;

  /// Bağlam yetersizse sorulan tek soru.
  final String? clarifyQuestion;

  /// Soruyla birlikte sunulan görev türleri.
  final List<TaskType> options;

  bool get needsClarification => decision == null;

  /// Yerel modele ve geçmişe aktarılan düz metin özeti.
  String toPlainText() {
    if (needsClarification) return clarifyQuestion ?? '';
    final sb = StringBuffer()
      ..writeln('Karar: ${decision!.label}')
      ..writeln('Gerekçe: $reason')
      ..writeln('Yapay zekâsız yol: $firstStep');
    if (supportLimit != null) sb.writeln('Destek sınırı: $supportLimit');
    return sb.toString().trim();
  }
}

/// Boş veya değerlendirilemeyen giriş için hata.
class EmptyInputException implements Exception {
  const EmptyInputException();
  String get message => 'Önce yapmak istediğin işi bir cümleyle yaz.';
  @override
  String toString() => message;
}
