# İtiraz Botu

Kendi kullanımını da sorgulayan, tamamen çevrimdışı çalışan bir yapay zekâ uygulaması.
"Bu işi yapay zekâya yaptırayım mı?" diye sorarsın ya da doğrudan yapmak istediğin işi
yazarsın. Bot her yanıtta dört şey verir:

| | |
|---|---|
| **Karar** | Kendin yap · Sınırlı destek al · Yapay zekâya devredebilirsin |
| **Gerekçe** | Bu işe özel, bir iki sade cümle |
| **Yapay zekâsız yol** | Hemen denenebilecek somut bir adım |
| **Destek sınırı** | Uygunsa yapay zekânın yardım edebileceği en küçük parça |

Bağlam yetersizse kesin karar uydurmaz: tek bir soru sorar ve görev türünü seçtirir.
Gizlilik, öğrenme, kişisel ifade ve kararın sonuçları gerekçeyi etkiler ve sonuç kartında
"Etkileyen" olarak yazılır.

Windows, Linux, macOS, Android ve iPhone için tek Flutter projesidir.

---

## İçindekiler

1. [Mimari](#mimari)
2. [Windows 11'de hızlı başlangıç](#windows-11de-hızlı-başlangıç)
3. [Linux](#linux)
4. [macOS](#macos)
5. [Android](#android)
6. [iPhone (iOS)](#iphone-ios)
7. [Geliştirme ve testler](#geliştirme-ve-testler)
8. [Model aktarımı ve "model dâhil" paket](#model-aktarımı-ve-model-dâhil-paket)
9. [Çevrimdışı doğrulama](#çevrimdışı-doğrulama)
10. [Gizlilik](#gizlilik)
11. [Doğrulama durumu](#doğrulama-durumu)
12. [Sorun giderme](#sorun-giderme)

---

## Mimari

```
lib/
  main.dart                  Giriş noktası
  src/core/                  KURALLI DEĞERLENDİRME (saf Dart, test edilebilir)
    text_norm.dart           Türkçe küçük harf (I→ı, İ→i), aksan katlama, kök eşleşmesi
    rule_engine.dart         Öncelik sıralı kurallar + gizlilik değiştiricisi
    verdict.dart             Karar / gerekçe / ilk adım / destek sınırı modelleri
  src/llm/                   YEREL MODEL (isteğe bağlı)
    native_bindings.dart     dart:ffi → itiraz_native
    local_model_service.dart Ayrı isolate'te yükleme ve üretim, iptal, bellek denetimi
    gguf_inspector.dart      GGUF başlık denetimi (biçim, sürüm, yarım dosya, mimari)
    model_store.dart         İçe aktarma (ilerleme, iptal, boş alan), paket modeli
  src/data/app_state.dart    Ayarlar ve geçmiş (yalnızca cihazdaki JSON)
  src/ui/                    Ekranlar
native/
  itiraz_native.cpp          llama.cpp üstünde sade C köprüsü (yükle, başlat, sıradaki, iptal,
                             boş disk, boş bellek)
  CMakeLists.txt             llama.cpp'yi statik derleyip tek kütüphaneye bağlar
  apple/ItirazNative.podspec iOS/macOS için xcframework'ü gömer
third_party/llama.cpp        git alt modülü, sabit sürüm: b11900 (74b104c9, 26.10.2026)
tool/
  make_test_model.py         İnternetsiz, rastgele ağırlıklı test modeli üretir
  bundle_model.py            "Model dâhil" paket için modeli parçalara böler
  build_apple.sh             iOS + macOS xcframework derler
  test_native.sh             Yerel model testlerini Linux'ta çalıştırır
```

**İki mod, her zaman etiketli:**

- **Kurallı değerlendirme** (varsayılan): Dart kural motoru. Model, internet ya da kurulum
  gerektirmez; ilk açılışta da çalışır.
- **Yerel model**: Yalnızca kullanıcı sonuç ekranında "Yerel modelle ayrıntılandır" dediğinde
  çalışır. llama.cpp cihazda, ayrı bir isolate'te çalışır; arayüz donmaz, "Durdur" (ya da
  Esc) üretimi hemen keser. Model açılamazsa, uyumsuzsa ya da bellek yetmezse durum yazılır ve
  kurallı sonuç ekranda kalır.

**Sabitlenen sürümler:** Flutter 3.47.9 (Dart 3.13.7) · llama.cpp b11900 · Inter yazı tipi
(OFL-1.1, pakette). GPU/Metal kapalıdır: her platformda aynı CPU yolu (Apple'da Accelerate).

---

## Windows 11'de hızlı başlangıç

### 1. Araçları kur (bir kez)

1. **Git**: <https://git-scm.com/download/win> (kurulumda varsayılanlar yeterli).
2. **Visual Studio 2022** (Community yeterli). Kurulumda **"Desktop development with C++"**
   iş yükünü seç. Bu, MSVC derleyicisini ve CMake'i getirir.
3. **Flutter 3.47.9**: <https://docs.flutter.dev/get-started/install/windows> sayfasından
   zip'i indir, `C:\src\flutter` klasörüne aç ve `C:\src\flutter\bin` yolunu PATH'e ekle.
4. Yeni bir PowerShell aç ve denetle:

```powershell
flutter --version          # 3.47.9 görünmeli
flutter doctor             # "Visual Studio - develop Windows apps" yeşil olmalı
flutter config --no-analytics
```

### 2. Projeyi al ve çalıştır

```powershell
git clone --recurse-submodules https://github.com/kaansavukduran/itirazbotu.git
cd itirazbotu
# Alt modül eksikse:  git submodule update --init --recursive
flutter pub get
flutter run -d windows
```

İlk derleme llama.cpp'yi de derlediği için birkaç dakika sürer.

### 3. Kurulabilir çıktı (mağazasız)

```powershell
flutter build windows --release
# Çıktı: build\windows\x64\runner\Release\
#   itiraz_botu.exe, itiraz_native.dll, flutter_windows.dll, data\
Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath dist\itiraz-botu-windows-x64.zip
```

Zip'i başka bir Windows 11 makinesinde açıp `itiraz_botu.exe` dosyasını çalıştırmak yeterli.
Hedef makinede "VCRUNTIME140.dll bulunamadı" hatası çıkarsa Microsoft Visual C++
Redistributable (x64) kurulmalıdır; bunu da önceden indirip çevrimdışı kurabilirsiniz.

---

## Linux

```bash
sudo apt install git clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
git clone --recurse-submodules https://github.com/kaansavukduran/itirazbotu.git
cd itirazbotu
flutter pub get
flutter run -d linux

# Kurulabilir çıktı
flutter build linux --release
tar -C build/linux/x64/release -czf dist/itiraz-botu-linux-x64.tar.gz \
    --transform 's/^bundle/itiraz-botu/' bundle
# Hedefte: tar xzf itiraz-botu-linux-x64.tar.gz && ./itiraz-botu/itiraz_botu
```

Dosya seçici XDG masaüstü portalını kullanır. Portal olmayan masaüstlerinde (ör. yalın pencere
yöneticileri) Ayarlar'daki **"Yolu elle gir"** düğmesiyle model dosyasının yolu yazılabilir.

---

## macOS

Gerekenler: macOS 13+, Xcode 16+, CocoaPods (`sudo gem install cocoapods` ya da
`brew install cocoapods`), CMake (`brew install cmake`).

```bash
git clone --recurse-submodules https://github.com/kaansavukduran/itirazbotu.git
cd itirazbotu
./tool/build_apple.sh              # native/apple/itiraz_native.xcframework üretir
flutter pub get
cd macos && pod install && cd ..
flutter run -d macos

flutter build macos --release      # build/macos/Build/Products/Release/itiraz_botu.app
```

Release yetkilerinde (`macos/Runner/Release.entitlements`) **ağ istemcisi izni yoktur**; sanal
alan (sandbox) giden bağlantıyı işletim sistemi düzeyinde engeller. Yalnızca kullanıcının
seçtiği dosyayı okuma izni vardır.

Başkasına vermek için uygulamayı bir Developer ID ile imzalayıp noterleştirmek gerekir
(Xcode → Product → Archive → Distribute App → Developer ID). İmzasız `.app` yalnızca kendi
makinenizde, sağ tık → Aç ile çalışır.

---

## Android

Gerekenler: Android Studio (SDK Manager'dan **Android SDK Platform 36**, **NDK** (Flutter'ın
istediği sürüm, `flutter doctor -v` gösterir) ve **CMake 3.22.1**), JDK 17.

```bash
git clone --recurse-submodules https://github.com/kaansavukduran/itirazbotu.git
cd itirazbotu
flutter pub get
flutter run -d <cihaz-kimliği>            # flutter devices ile listele

# Kurulabilir çıktı (mağazasız, imza: debug anahtarı)
flutter build apk --release --split-per-abi
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Yerel köprü `android/app/build.gradle.kts` içindeki `externalNativeBuild` ile
`native/CMakeLists.txt` üzerinden `arm64-v8a` ve `x86_64` için derlenir (16 KB sayfa uyumlu).
Release manifestinde `INTERNET` izni **yoktur** (debug/profile manifestlerindeki izin yalnızca
Flutter geliştirme araçları içindir). Ayrıca `allowBackup="false"`: geçmiş buluta yedeklenmez.

Model içe aktarma Android'de sistem dosya seçicisiyle yapılır; seçici dosyayı önce geçici
klasöre kopyalayabilir, bu yüzden boş alanın model boyutunun yaklaşık iki katı olması önerilir.

---

## iPhone (iOS)

iPhone derlemesi **yalnızca macOS ve Xcode ile** yapılabilir.

### Gerekenler

- macOS 14+ ve Xcode 16+ (App Store), Xcode açılıp ek bileşenler kurulmuş olmalı.
- CocoaPods ve CMake (`brew install cocoapods cmake`).
- Bir Apple Kimliği. Ücretsiz hesapla kendi cihazına 7 gün geçerli kurulum yapılabilir;
  ücretli Apple Developer Program ile 1 yıl ve ad hoc dağıtım mümkündür.
- iOS 15 veya üstü bir iPhone ve USB-C/Lightning kablosu.

### Adımlar

```bash
git clone --recurse-submodules https://github.com/kaansavukduran/itirazbotu.git
cd itirazbotu
./tool/build_apple.sh                 # iOS cihaz + simülatör + macOS xcframework
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```

### İmzalama

1. Xcode'da sol tarafta **Runner** projesi → **Runner** hedefi → **Signing & Capabilities**.
2. **Automatically manage signing** işaretli olsun, **Team** olarak Apple Kimliğini seç
   (Xcode → Settings → Accounts'tan ekleyebilirsin).
3. **Bundle Identifier** benzersiz olmalı, örn. `com.adiniz.itirazbotu`.

### Gerçek cihazda çalıştırma

1. iPhone'u bağla, "Bu bilgisayara güven" de.
2. iPhone'da **Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu**'nu aç, cihaz yeniden başlar.
3. Terminalde:

```bash
flutter devices                         # iPhone'un kimliğini gör
flutter run --release -d <iphone-kimliği>
```

4. İlk açılışta "Güvenilmeyen geliştirici" uyarısı çıkarsa: **Ayarlar → Genel → VPN ve
   Aygıt Yönetimi →** geliştirici sertifikana dokun → **Güven**.

### Mağazasız kurulabilir çıktı

```bash
flutter build ipa --release --export-method development   # ya da ad-hoc (ücretli hesap)
# build/ios/ipa/*.ipa → Xcode → Window → Devices and Simulators → "+" ile cihaza kur
```

### iPhone'a model aktarma

GGUF dosyasını AirDrop, kablo (Finder → iPhone → Dosyalar) ya da USB bellekle **Dosyalar**
uygulamasına koy ("iPhone'umda" klasörü önerilir; iCloud'daysa önce indirilmiş olmalı).
Uygulamada **Ayarlar → Dosyadan model ekle** ile seç. 4 GB RAM'li iPhone'larda 0,5–1,5 milyar
parametreli Q4 modeller önerilir; daha büyükleri bellek denetimine takılır.

---

## Geliştirme ve testler

```bash
flutter analyze
flutter test                   # kural motoru, model deposu, arayüz akışı
./tool/test_native.sh          # Linux: llama.cpp köprüsünü derler, test modeli üretir,
                               # gerçek yükleme/üretim/iptal testlerini çalıştırır
```

Testlerin kapsadığı durumlar:

| Test dosyası | Kapsam |
|---|---|
| `test/rule_engine_test.dart` | Dört örnek senaryo, Türkçe karakterler (İ/I, ç, ğ, ş, aksansız yazım), boş giriş, yalnızca noktalama, bilinmeyen görev → soru, tür seçimi, gizlilik/sağlık/hukuk/öğrenme etkenleri, yanlış eşleşme tuzakları ("bugün" ≠ "bug", "öğrenci" ≠ "öğren"), çok uzun giriş |
| `test/model_store_test.dart` | İçe aktarma ilerlemesi, iptal (yarım dosya silinir), yetersiz boş alan, GGUF olmayan dosya, kesik dosya, desteklenmeyen sürüm, bilinmeyen mimari, paket modeli birleştirme |
| `test/app_flow_test.dart` | İlk ekran, boş giriş, örneğe dokunma, ekran okuyucu etiketleri, Ctrl+Enter, açıklayıcı soru ve tür seçimi, geçmiş (varsayılan kapalı, açma, tek dokunuşla temizleme, dosyanın silinmesi), büyük yazı, koyu tema, 48 px dokunma alanı |
| `test/local_model_test.dart` | Gerçek llama.cpp: model yükleme ve ilerleme, gerçek belirteç üretimi, üretimi durdurma ve sonra yeniden üretme, yükleme iptali, bozuk model, başlığı geçerli ama açılamayan model, bellekten çıkarma, boş disk/bellek ölçümü |

`local_model_test.dart`, `ITIRAZ_NATIVE_LIB` ve `ITIRAZ_TEST_MODEL` ortam değişkenleri yoksa
atlanır; `tool/test_native.sh` bunları kendisi ayarlar.

---

## Model aktarımı ve "model dâhil" paket

### Hangi model?

- Biçim: **GGUF** (llama.cpp b11900 ile uyumlu). Uygulama dosyayı açmadan önce sihirli
  baytları, GGUF sürümünü (2–3), tensör ofsetlerini (yarım dosya) ve mimariyi denetler.
- Boyut: telefon ve 8 GB RAM'li bilgisayarlar için 0,5–1,5 milyar parametre, **Q4_K_M**.
- Öneri: **Qwen2.5-0.5B-Instruct** veya **Qwen2.5-1.5B-Instruct** (Apache-2.0, dağıtıma
  izin verir, çok dilli). Türkçe kalitesini kendi cihazınızda deneyin; bu depo hazırlanırken
  model indirme sunucularına erişim olmadığı için Türkçe yanıt kalitesi **denenmedi**.

Modeli internetli bir makinede bir kez indirip (ör. Hugging Face'teki resmi GGUF deposundan)
USB bellek, AirDrop ya da kabloyla hedef cihaza taşıyın. Uygulamanın kendisi hiçbir şey
indirmez.

### İçe aktarma

**Ayarlar → Yerel model → Dosyadan model ekle (.gguf)**. Uygulama:

1. GGUF başlığını denetler (Türkçe hata: "Bu bir GGUF model dosyası değil", "Model dosyası
   yarım", "GGUF sürüm N desteklenmiyor"…),
2. Boş alanı ölçer (model + 64 MB pay),
3. Dosyayı ilerleme çubuğuyla uygulama dizinine kopyalar; **İptal** yarım dosyayı siler,
4. "Yükle" ile modeli açar; yüklemede de ilerleme ve iptal vardır. Boş bellek
   (model × 1,1 + 256 MB) yetmezse model açılmadan durum yazılır.

### "Model dâhil" paket

```bash
python3 tool/bundle_model.py qwen2.5-0.5b-instruct-q4_k_m.gguf \
    --name "Qwen2.5 0.5B Instruct" --license "Apache-2.0"
flutter build <windows|linux|macos|apk|ipa> --release
python3 tool/bundle_model.py --clean        # paketi yeniden modelsiz yapar
```

Model 64 MB'lık parçalar hâlinde `assets/bundled_model/` içine konur (git'e eklenmez).
Uygulama ilk kullanımda **Ayarlar → Paketteki modeli kullan** ile parçaları cihazda birleştirir
(ağ yok) ve modeli yükler. Model lisansını paketle birlikte dağıtmayı unutmayın.

---

## Çevrimdışı doğrulama

Her platformda şu dört kontrolü ayrı ayrı yapın. **Bir platformun derlenmesi, cihazda
çevrimdışı çalıştığının kanıtı değildir.**

1. **Temiz ilk açılış, ağ kapalı**: Uygulama verisini sil, ağı kapat, uygulamayı aç.
2. **Kurallı karar**: Üç örneğin her birine dokun; karar, gerekçe, ilk adım ve
   "Kurallı değerlendirme" etiketi görünmeli.
3. **Yerel dosyadan model yükleme**: Ağ kapalıyken bir GGUF dosyasını içe aktar ve yükle.
4. **Modelle gerçek yanıt**: "Yerel modelle ayrıntılandır"a bas; metin akarak gelmeli,
   "Durdur" çalışmalı, etiket "Yerel model · <ad>" olmalı.

| Platform | Temiz başlangıç (veriyi sil) | Ağı kapatma ve izleme |
|---|---|---|
| Windows 11 | `Remove-Item -Recurse "$env:APPDATA\com.itirazbotu\Itiraz Botu"` | Uçak modu ya da `New-NetFirewallRule -DisplayName ItirazBotuEngel -Direction Outbound -Program "<tam yol>\itiraz_botu.exe" -Action Block`; Kaynak İzleyicisi → Ağ sekmesinde uygulamanın bağlantısı olmamalı |
| Linux | `rm -rf ~/.local/share/com.itirazbotu.itiraz_botu` | Ağ ad alanı olmadan: `unshare -rn ./itiraz_botu` (yalnızca `lo` görünür); `strace -f -e trace=connect ./itiraz_botu` çıktısında yalnızca `AF_UNIX` olmalı |
| macOS | `rm -rf ~/Library/Containers/com.itirazbotu.itirazBotu` | Wi-Fi kapalı; `nettop -p itiraz_botu`; Release sandbox'ında ağ izni yok |
| Android | `adb shell pm clear com.itirazbotu.itiraz_botu` | Uçak modu; `adb shell dumpsys package com.itirazbotu.itiraz_botu \| grep -i internet` boş olmalı |
| iPhone | Uygulamayı silip yeniden kur | Uçak modu + Wi-Fi kapalı; **Ayarlar → Gizlilik ve Güvenlik → Uygulama Gizlilik Raporu**'nda uygulamanın ağ etkinliği olmamalı |

---

## Gizlilik

- Hesap, telemetri, reklam, analiz ve uzaktan güncelleme yoktur.
- Yazı tipleri, simgeler ve örnekler pakettedir; çalışma anında hiçbir şey indirilmez.
- Geçmiş **varsayılan olarak kapalıdır**. Açılırsa yalnızca cihazdaki `history.json`
  dosyasına yazılır; **Geçmişi temizle** dosyayı siler, geçmişi kapatmak da kayıtları siler.
- Model dosyaları yalnızca uygulamanın kendi dizinine kopyalanır.

---

## Doğrulama durumu

Bu depo hazırlanırken yalnızca bir Linux (x86_64) bulut konteyneri vardı. Windows makinesi,
Mac, Android SDK (dl.google.com erişimi kapalıydı) ve iPhone yoktu; model sunucularına
(Hugging Face) erişim de kapalıydı.

| Platform | Derlendi | Cihazda çalıştırıldı | Çevrimdışı ilk açılış doğrulandı | Yerel model doğrulandı |
|---|---|---|---|---|
| Linux x64 | ✅ `flutter build linux --release` | ✅ Xvfb altında, gerçek uygulama | ✅ ağ ad alanı yalnızca `lo`, temiz HOME, `strace`: yalnızca `AF_UNIX` | ⚠️ Kısmen: rastgele ağırlıklı test modeli içe aktarıldı, yüklendi, arayüzde akışla belirteç üretti; paket modeli de çalıştı. Gerçek Türkçe model denenmedi |
| Windows 11 | ❌ MSVC yok (köprünün Windows kodu yalnızca MinGW sözdizimi denetiminden geçti) | ❌ | ❌ | ❌ |
| macOS | ❌ Xcode yok | ❌ | ❌ | ❌ |
| Android | ❌ Android SDK/NDK indirilemedi | ❌ | ❌ | ❌ |
| iPhone | ❌ macOS/Xcode yok | ❌ | ❌ | ❌ |

Sıradaki komutlar: Windows'ta `flutter build windows --release`; macOS'ta
`./tool/build_apple.sh && flutter build macos --release`; Android'de
`flutter build apk --release --split-per-abi`; iPhone'da yukarıdaki iOS adımları. Ardından
her platformda [Çevrimdışı doğrulama](#çevrimdışı-doğrulama) tablosunu uygulayın.

---

## Sorun giderme

| Belirti | Çözüm |
|---|---|
| `llama.cpp bulunamadı` (CMake) | `git submodule update --init --recursive` |
| Ayarlar'da "Yerel model bu kurulumda kullanılamıyor" | Köprü kütüphanesi pakette değil: Windows'ta `itiraz_native.dll`, Linux'ta `lib/libitiraz_native.so` exe'nin yanında olmalı; Apple'da önce `tool/build_apple.sh` ve `pod install` |
| "Dosya seçici açılamadı" (Linux) | XDG portalı yok: `sudo apt install xdg-desktop-portal-gtk` ya da "Yolu elle gir" |
| "Cihaz belleği bu model için yetmiyor" | Daha küçük ya da daha çok nicemlenmiş (Q4) bir model seçin, diğer uygulamaları kapatın |
| "Metin, modelin bağlam penceresi için çok uzun" | Modelin bağlamı çok kısa (ör. 512); en az 2048 bağlamlı bir model kullanın |
| Model yanıtı anlamsız | Test modeli rastgele ağırlıklıdır; gerçek bir Instruct modeli içe aktarın |
