<p align="center"><img src="Resources/AppIcon.png" width="128" alt="Kadraj"></p>

# Kadraj

**macOS için açık kaynak ekran görüntüsü aracı.** Admin yetkisi, Homebrew veya App Store gerektirmeden tek komutla kurulur — şirket bilgisayarları dahil.

[English](README.en.md)

> ⚠️ Erken sürüm: tüm temel özellikler hazır, geri bildirimlerle iyileştiriliyor.

## Kurulum

```bash
# Son sürüm
curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash

# Belirli bir sürüm (başında v olsa da olmasa da olur)
curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash -s -- 1.2.0

# Geliştirme dalı (main'den derlenen nightly)
curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash -s -- main
```

Gereksinim: macOS 14 Sonoma veya üstü (Apple Silicon ve Intel).

### Neden admin yetkisi gerekmiyor?

- `/Applications`'a yazabiliyorsanız oraya, yazamıyorsanız `~/Applications`'a kurulur. Script hiçbir adımda yönetici parolası istemez.
- Uygulama Apple Developer ID ile imzalanır ve Apple tarafından notarize edilir; Gatekeeper uyarısı çıkmaz.
- İndirilen arşivin SHA-256 özeti doğrulanır; doğrulama başarısız olursa mevcut kurulum değiştirilmez.

### İzinler

Kadraj'ın ihtiyaç duyduğu tek izin **Ekran Kaydı**dır. İlk açılışta Kadraj sizi yönlendirir: *Sistem Ayarları → Gizlilik ve Güvenlik → Ekran Kaydı* altında Kadraj'ı açın, ardından Kadraj'ı yeniden başlatın.

macOS 15 ve sonrası, ekranı doğrudan yakalayan uygulamalar için zaman zaman *"Kadraj is requesting to bypass the system private window picker…"* uyarısı gösterir. Bu, ScreenCaptureKit kullanan tüm ekran görüntüsü araçlarında görülen bir sistem onayıdır; **Allow** ile devam edebilirsiniz.

Şirket bilgisayarında bu izin MDM ile kapatılmışsa IT ekibiniz [docs/MDM.md](docs/MDM.md)'deki profil ile standart kullanıcıların izni kendilerinin vermesine olanak tanıyabilir.

### Güncelleme ve girişte başlatma

Menüden **Güncellemeleri Kontrol Et…**: yeni sürüm varsa **Güncelle** ile indirilir, SHA-256 doğrulanır ve Kadraj yerinde değiştirilip yeniden başlatılır — yönetici izni gerekmez (Kadraj yazılabilir bir klasörde olduğu sürece). Kadraj kendiliğinden internete bağlanmaz; kontrol yalnızca sen istediğinde yapılır. Kurulum komutunu tekrar çalıştırmak da güncellemedir.

**Ayarlar → Genel → Girişte başlat** ile Kadraj oturum açınca kendiliğinden açılır.

### Kaldırma

```bash
curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/uninstall.sh | bash
```

## Kullanım

Kadraj menü çubuğunda vizör ikonuyla çalışır.

| Kısayol | İşlem |
|---|---|
| `⌥⇧A` | Alan seç: bırakınca seçimin altında **araç çubuğu** açılır — oku, kutuyu, metni, bulanıklaştırmayı doğrudan ekranda çiz; sonra **Kopyala** (⌘C), **Kaydet** (⌘S), **Pinle**, **Metin** (OCR), **QR**, **Editör** veya **Bitti** (Return). Esc iptal, Space pencere modu |
| `⌥⇧W` | Pencere yakala (gölge ayarlardan açılıp kapatılabilir) |
| `⌥⇧F` | İmlecin bulunduğu ekranın tamamı |
| `⌥⇧S` | Kaydırarak yakala: alanı seç, içeriği aşağı kaydır, **Bitti**'ye bas (uzun sayfalar, sohbetler) |
| `⌥⇧R` | Ekran kaydı: alan seç (ya da tüm ekran için tıkla); tekrar `⌥⇧R` veya menü çubuğundaki kırmızı simge → **Kaydı Durdur**. MP4 olarak kaydedilir, bildirimden **GIF'e Dönüştür** |
| `⌥⇧O` | Alandaki metni tanı ve panoya kopyala (tamamen internetsiz; Türkçe, Vision'ın Türkçe modelini içeren yeni macOS sürümlerinde) |
| `⌥⇧C` | Renk seç: ekrandan bir piksele tıkla, renk HEX / RGB / HSL olarak panoya kopyalanır (biçim Ayarlar'da) |
| `⌥⇧M` | Cetvel: dondurulmuş ekranda sürükleyerek ölç (pt ve px); Return ölçüyü kopyalar |
| `⌥⇧Q` | Alandaki QR kodu / barkodu oku ve panoya kopyala (bağlantıysa "Aç") |

Yakalamadan sonra sağ altta **Quick Access** küçük resmi çıkar: kopyala, kaydet, Finder'da göster ya da istediğin yere sürükle. Görüntüler varsayılan olarak `~/Pictures/Kadraj` klasörüne kaydedilir ve panoya kopyalanır. Kısayollar, klasör ve biçim (PNG/JPEG) **Ayarlar**'dan değiştirilebilir.

### İşaretleme editörü

Quick Access'te **Düzenle**'ye bas ya da küçük resme çift tıkla. Araçlar ve tek tuş kısayolları:

| Tuş | Araç | Tuş | Araç |
|---|---|---|---|
| `V` | Seç / taşı (⌫ siler, çift tık metni düzenler) | `T` | Metin |
| `A` | Ok | `N` | Numaralı adım (1, 2, 3…) |
| `L` | Çizgi | `B` | Bulanıklaştır |
| `R` | Dikdörtgen | `M` | Mozaik |
| `O` | Elips | `C` | Kırp |
| `P` | Kalem | `H` | Vurgulayıcı |

`⇧` ile çizgi/ok 45°'ye, dikdörtgen/elips kareye kilitlenir. `⌘Z` / `⇧⌘Z` geri al / yinele, `⌘C` kopyala, `⌘S` kaydet (orijinal dosyanın üzerine), `⇧⌘S` farklı kaydet. Renk ve kalınlık seçiliyken seçili işaretlemeyi de değiştirir.

### Ekrana pinleme

Quick Access'te veya editörde **Pinle**'ye bas ya da menüden **Panodaki Görüntüyü Pinle**'yi seç. Pin her zaman üstte durur: sürükleyerek taşı, kaydırma tekerleği / pinch ile yakınlaştır, çift tık veya Esc ile kapat. Sağ tık menüsünde opaklık, tıklamaları geçir, kopyala, kaydet, düzenle ve metni kopyala var. Tıklamaları geçiren pinleri menü çubuğundan **Pinleri Etkileşimli Yap** ile geri alabilirsin.

Otomasyon (Raycast, Alfred, Kestirmeler) için:

```bash
open "kadraj://capture/area"   # ya da window, fullscreen, scroll, record, text, qr, color, ruler
open "kadraj://settings"
open "kadraj://check-updates"
```

## Yol haritası

- [x] Menü çubuğu uygulaması, izin onboarding'i, curl kurulumu
- [x] Alan / pencere / tam ekran görüntüsü, Quick Access, ayarlar
- [x] OCR (Türkçe dahil, internetsiz) ve QR okuma; Quick Access'ten "Metni Kopyala"
- [x] İşaretleme editörü (ok, kutu, metin, bulanıklaştırma, mozaik, numaralı adımlar, kırpma…)
- [x] Ekrana pinleme
- [x] Scroll ile uzun ekran görüntüsü
- [x] Ekran kaydı (MP4) ve GIF
- [x] Renk seçici ve cetvel

## Kaynaktan derleme

Swift 6 (Xcode 16+ veya Command Line Tools) gerekir; `.xcodeproj` yoktur, her şey SwiftPM ile derlenir.

Kodu düzenlemek için Xcode ile açabilirsin (`xed .`). Çalıştırmak için `scripts/dev.sh` kullan: derler, `.app` olarak paketler, imzalar ve yeniden başlatır. Xcode'un Run düğmesi Info.plist'i yüklemediği için URL şeması ve izinler orada düzgün çalışmaz.

```bash
swift test                 # birim testleri
scripts/dev.sh             # hızlı geliştirme döngüsü (dist-dev/Kadraj.app)
scripts/bundle.sh          # dist/Kadraj.app (universal, ad-hoc imzalı)
open dist/Kadraj.app
/bin/bash Tests/install_test.sh   # kurulum scripti testleri
```

> Command Line Tools ile `swift build` manifest hatası verirse (`Undefined symbols … PackageDescription`), Xcode'un araç zincirini kullanın: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Sürüm yayınlama (bakımcılar için)

`v*` etiketi push edildiğinde GitHub Actions uygulamayı derler, imzalar, notarize eder ve `Kadraj.zip` + `Kadraj.zip.sha256` dosyalarını release'e yükler. `main`'e her push `nightly` ön sürümünü günceller.

Gerekli repository secret'ları (yoksa uygulama ad-hoc imzalanır ve notarize edilmez):

| Secret | İçerik |
|---|---|
| `DEVELOPER_ID_P12` | "Developer ID Application" sertifikası + özel anahtarı, `.p12` olarak dışa aktarılmış, `base64` |
| `DEVELOPER_ID_P12_PASSWORD` | `.p12` parolası |
| `DEVELOPER_ID_NAME` | `Developer ID Application: Ad Soyad (TEAMID)` |
| `NOTARY_KEY_ID` | App Store Connect API anahtar ID'si |
| `NOTARY_ISSUER_ID` | App Store Connect issuer ID |
| `NOTARY_KEY_P8` | `AuthKey_XXXX.p8` dosyası, `base64` |

```bash
base64 -i DeveloperID.p12 | gh secret set DEVELOPER_ID_P12
gh secret set DEVELOPER_ID_P12_PASSWORD
gh secret set DEVELOPER_ID_NAME --body "Developer ID Application: Ad Soyad (TEAMID)"
gh secret set NOTARY_KEY_ID --body "XXXXXXXXXX"
gh secret set NOTARY_ISSUER_ID --body "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
base64 -i AuthKey_XXXXXXXXXX.p8 | gh secret set NOTARY_KEY_P8

git tag v0.1.0 && git push origin v0.1.0
```

## Lisans

[MIT](LICENSE) © 2026 Mahir Uslu
