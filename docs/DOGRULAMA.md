# Doğrulama kaydı · 9 Kasım 2026

Bu kayıt, `5ffb98f` üzerine yapılan devam çalışmasının sonuçlarını ayırır.
Derleme, cihazda çalıştırma, çevrimdışı ilk açılış ve gerçek model kullanımı
birbirinin yerine sayılmaz.

| Platform | Derlendi | Cihazda çalıştırıldı | Çevrimdışı ilk açılış doğrulandı | Yerel model doğrulandı |
|---|---|---|---|---|
| Linux x64 | Evet, release | Evet, Xvfb üzerinde gerçek masaüstü uygulaması | Evet, temiz veri dizini ve yalnızca `lo` arayüzü | Evet, eğitimli Qwen GGUF içe aktarma/yükleme/üretim; dil kalitesi sınırlı |
| Android ARM64 ve x64 | Evet, iki release APK | Hayır | Hayır | Hayır; yerel köprünün derlenmesi cihaz testi değildir |
| Windows 11 | Bu çalışma ortamında hayır | Hayır | Hayır | Hayır |
| macOS | Bu çalışma ortamında hayır | Hayır | Hayır | Hayır |
| iPhone | Bu çalışma ortamında hayır | Hayır | Hayır | Hayır |

## Kullanılan araçlar

- Flutter **3.47.9**, Dart **3.13.7**; mevcut `pubspec.lock` korunmuştur.
- llama.cpp alt modülünün gerçek sabit kimliği:
  `a691b2345844ce1b430201fc5fd404ce062e05f2`. Önceki README'deki `b11900`
  ifadesi git alt modülüyle uyuşmuyordu; doküman ve arayüz düzeltildi.
- Linux: Debian 13 x86_64, Clang 19, CMake 3.31.6, Ninja, GTK 3, Xvfb.
- Android: JDK 21, SDK Platform 36, NDK **28.2.13676358**, CMake **3.22.1**.
  Bir dosya seçici bağımlılığı için Platform 35 de derleme sırasında kuruldu.
- Yerel C köprüsünün ABI sürümü **2**. Dart ve kütüphane birlikte derlenmelidir.

## Testler

Son genel turda **75 test geçti**, **1 isteğe bağlı eğitimli model testi atlandı**.
Bu turda `ITIRAZ_NATIVE_LIB`, `ITIRAZ_TEST_MODEL` ve `ITIRAZ_BAD_MODEL`
tanımlıydı; yerel köprü testleri atlanmadı. `flutter analyze` ayrıca çalıştırıldı.

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
./tool/test_native.sh
```

Genel testlere ek olarak iki eğitimli model, `test/real_model_test.dart` ile
ayrı ayrı yerelden içe aktarıldı, yüklendi ve üç örnekte gerçek belirteç üretti.
Bu test çalıştırılabilirliği sınar; iyi Türkçe veya doğru öneri garantisi vermez.

```bash
ITIRAZ_NATIVE_LIB="$PWD/build/native/libitiraz_native.so" \
ITIRAZ_REAL_MODEL="/tam/yol/model.gguf" \
ITIRAZ_REAL_REPORT="$PWD/build/real-model-report.json" \
flutter test test/real_model_test.dart
```

Eklenen regresyon kontrolleri: geçmiş yazılırken temizleme, hızlı gizlilik
tercihlerinin diskteki sırası, yeni görevden sonra geç gelen model parçaları,
aynı turda üretimi durdurma, başlık denetlenirken yüklemeyi iptal etme ve ikinci
yüklemeyi engelleme, son tensörün tek baytı eksik GGUF, son paket parçasında
iptal, paket bütünlüğü ve 320 piksel telefonda büyük yazı.

## Linux'ta çevrimdışı arayüz

Release uygulaması, yeni `XDG_DATA_HOME` ve `XDG_CONFIG_HOME` ile Xvfb üzerinde
`unshare -Urn` içinde çalıştırıldı. Ağ alanında yalnızca `lo` vardı. İlk açılış,
örnekten kurallı karar, yerel dosya yolundan GGUF aktarımı, yükleme ve model
üretimi arayüzden denendi. İlk denemenin `connect` izinde **0 AF_INET/AF_INET6**
ve yalnızca yerel Unix soketi bağlantıları görüldü.

Kendi masaüstünüzde tekrar etmek için:

```bash
flutter build linux --release
./tool/check_offline_linux.sh
```

Bu betik temiz veri dizini oluşturur; tüm ağ sistem çağrılarını kaydeder.
Üç örneği, Ayarlar'dan yerel modeli ve üretimi elle deneyip uygulamayı kapatın.
Betik ağ denetimi yapar; arayüz/model adımlarının sonucunu kendiniz kaydedin.
`unshare` kısıtlanmışsa kullanıcı ağ ad alanlarını destekleyen bir Linux gerekir.

## Model kalitesi ve paket kararı

[Ham Türkçe denemeler](model-denemeleri.json), 160 belirteç sınırı ve sıcaklık 0
ile saklanmıştır. Rastgele test modeli bunların yerine kullanılmamıştır.

| Model | Kaynak revizyonu | Boyut | Lisans | Sonuç |
|---|---|---|---|---|
| Qwen2.5 0.5B Instruct Q4_K_M | `9217f5db79a29953eb74d5343926648285ec7e67` | 491.400.032 bayt | Apache-2.0 | Yükleme ve üretim çalıştı; istem tekrarı ve dil hataları görüldü |
| Qwen2.5 1.5B Instruct Q4_K_M | `91cad51170dc346986eccefdc2dd33a9da36ead9` | 1.117.320.736 bayt | Apache-2.0 | Yükleme ve üretim çalıştı; tekrar, yarım metin ve kullanıcı yerine görev yapma görüldü |

Kaynaklar: [0.5B](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF),
[1.5B](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF).

SHA-256 değerleri:

```text
0.5B  74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db
1.5B  6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e
```

Bu iki model için **Türkçe ürün kalitesi onaylanmadı**. Bu nedenle hazır
dağıtımlar modelsizdir. İlk açılışta kurallı değerlendirme tam çalışır; kullanıcı
kendi GGUF dosyasını çevrimdışı ekleyebilir. Açık istem tekrarı arayüzde hata
olarak gösterilir ve kurallı sonuç korunur. Diğer anlamsal hatalar otomatik
olarak bütünüyle saptanamaz.

Model dâhil paketleme yolu korunmuştur. Kendi denediğiniz uygun model için:

```bash
python3 tool/bundle_model.py /tam/yol/model.gguf \
  --name "Denenmiş model" --license "Apache-2.0" --license-file MODEL_LICENSE.txt
flutter build linux --release
python3 tool/bundle_model.py --clean
```

İçe aktarma ve paket birleştirme iptal edilebilir. Birleştirilen modelin GGUF
boyutları ve manifest SHA-256 özeti denetlenir. Tam model lisansı da paketlenir.

## Kurulabilir çıktılar

Çalışma alanındaki `dist/` altında Linux x64 arşivi ve Android ARM64/x64 APK'ları
üretilir. Dosyalar model içermez. Android paketleri debug anahtarıyla imzalı
release derlemeleridir; mağaza yayını için kullanıcıya ait imzalama gerekir.
APK izin dökümünde `INTERNET` yoktur. Bunun cihaz testi yerine geçmediğine dikkat edin.

## Diğer platformlar

GitHub Actions iş akışı Linux, Windows, Android, macOS ve iOS derleme adımlarını
içerir. Henüz çalışmamış veya tamamlanmamış bir işi başarılı saymayın. iOS CI
çıktısı imzasız `.app` arşividir; iPhone'a kurulabilir imzalı IPA değildir.

| Platform | Bu ortamda eksik erişim/araç | Sıradaki komut |
|---|---|---|
| Windows 11 | Windows ve Visual Studio 2022 C++ iş yükü/MSVC | `flutter build windows --release`, sonra `flutter run --release -d windows` |
| macOS | Mac, Xcode ve CocoaPods | `./tool/build_apple.sh && flutter build macos --release`, sonra `flutter run --release -d macos` |
| Android | USB cihaz; donanım emülasyonu için `/dev/kvm` de yok | `adb install dist/itiraz-botu-android-arm64.apk`, sonra uçak modunda uygulamayı aç |
| iPhone | Mac, Xcode, Apple imzalama ekibi ve gerçek iPhone | `./tool/build_apple.sh`, sonra `flutter run --release -d <iphone-kimliği>` |

Windows 11 kurulum/çalıştırma komutları ve iPhone'a özel imzalama, gerçek cihaz,
IPA oluşturma ve model aktarım adımları [README](../README.md) içindedir.
