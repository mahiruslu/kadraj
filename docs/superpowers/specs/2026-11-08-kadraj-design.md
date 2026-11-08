# Kadraj — açık kaynak macOS ekran görüntüsü aracı

## Bağlam
iShot / CleanShot X benzeri bir ekran görüntüsü uygulaması; açık kaynak (MIT), `github.com/mahiruslu/kadraj`.
Asıl ayırt edici nokta: **kısıtlı Mac'lere kurulabilmesi** — admin yetkisi yok, Homebrew/App Store yok, şirket MDM'i var.
Kurulum Mole tarzı tek komut olmalı:

```bash
curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash            # son sürüm
curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash -s -- 1.2.0 # belirli sürüm (v'li/v'siz)
curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash -s -- main  # main'den nightly
```

## Kararlar (kullanıcının verdiği)
- Özellikler v1: ekran görüntüsü (alan/pencere/tam ekran), scroll capture, OCR, işaretleme editörü, pinleme, ekran kaydı/GIF, renk seçici + cetvel + QR
- Kısıtlar: admin yok + MDM + Homebrew/App Store yok (üçü birden)
- İmzalama: **Developer ID var** → CI'da imzala + notarize
- Scroll capture: **manuel kaydırma** (kullanıcı kaydırır, uygulama birleştirir; Erişilebilirlik izni gerekmez)
- Min macOS: **14 Sonoma**
- İsim: **Kadraj**, lisans: **MIT**

## Benim kararlarım (itiraz edilebilir)
- **Swift 6 + Swift Package Manager**, `.xcodeproj` yok → katkı verenler Xcode'suz derleyebilir; `.app` paketi script ile oluşturulur. (Lokal makinede sadece Command Line Tools + Swift 6.4 var, yeterli.)
- Menü çubuğu uygulaması (`LSUIElement`, Dock ikonu yok), bundle id `com.mahiruslu.kadraj`.
- Sandbox yok, Mac App Store yok (curl dağıtımı için gereksiz, ScreenCaptureKit'i kısıtlar).
- Global kısayollar **Carbon `RegisterEventHotKey`** ile → Erişilebilirlik/Input Monitoring izni gerektirmez (MDM için kritik). Varsayılanlar sistemle çakışmasın: `⌥⇧A` alan, `⌥⇧W` pencere, `⌥⇧F` tam ekran, `⌥⇧S` scroll, `⌥⇧O` OCR, `⌥⇧R` kayıt, `⌥⇧C` renk; hepsi ayarlardan değiştirilebilir.
- **Tek gereken izin: Ekran Kaydı.** Renk seçici `NSColorSampler` (izinsiz), giriş başlatma `SMAppService.mainApp` (admin'siz).
- Ağ erişimi sadece güncelleme kontrolü (GitHub API); OCR dahil her şey offline.
- Arayüz Türkçe + İngilizce (String Catalog).
- `main` kurulumu = CI'ın main'deki her push'ta güncellediği `nightly` prerelease.

## Hedef dışı (v1)
Mac App Store, otomatik kaydırma, bulut yükleme, çeviri, geçmiş tarayıcısı, ses kaydı, Windows/Linux.

## Anti-hedefler (çalışsa bile başarısızlık sayılır)
- Kullanıcıdan `sudo`, Homebrew, Xcode veya derleme aracı istemek
- MDM kısıtlarını aşmaya çalışmak (izin yoksa nazikçe açıklar, IT için PPPC bilgisi verir)
- Telemetri / izinsiz ağ çağrısı

---

## Mimari

```
kadraj/
├─ Package.swift                 # macOS 14, Swift 6
├─ Sources/
│  ├─ KadrajCore/                # saf, test edilebilir mantık (AppKit'siz)
│  │  ├─ Stitching/              # scroll birleştirme (satır imzası + offset bulma)
│  │  ├─ Annotation/             # anotasyon modeli (value types) + CoreGraphics render
│  │  ├─ Vision/                 # OCR (VNRecognizeTextRequest), QR (VNDetectBarcodesRequest)
│  │  ├─ Export/                 # PNG/JPEG/GIF yazma (ImageIO), dosya adı şablonu
│  │  └─ Update/                 # sürüm karşılaştırma, release JSON parse
│  └─ Kadraj/                    # uygulama (AppKit + SwiftUI)
│     ├─ App/                    # AppDelegate, NSStatusItem menü, onboarding (izin)
│     ├─ Hotkeys/                # Carbon hotkey sarmalayıcı
│     ├─ Capture/                # SCShareableContent + SCScreenshotManager, seçim overlay
│     ├─ QuickAccess/            # yakalama sonrası köşe küçük resmi (kopyala/kaydet/düzenle/pin/OCR)
│     ├─ Editor/                 # işaretleme editörü penceresi
│     ├─ Pin/                    # yüzen NSPanel
│     ├─ Scroll/                 # SCStream ile kare toplama + HUD
│     ├─ Recording/              # SCStream → AVAssetWriter (mp4), GIF dönüştürme
│     ├─ Tools/                  # renk seçici, cetvel
│     └─ Settings/               # SwiftUI ayarlar
├─ Resources/                    # Info.plist şablonu, AppIcon.icns, Localizable.xcstrings
├─ Tests/KadrajCoreTests/
├─ scripts/bundle.sh             # swift build (universal) → Kadraj.app → codesign
├─ scripts/notarize.sh
├─ install.sh / uninstall.sh
├─ .github/workflows/ci.yml, release.yml, nightly.yml
└─ docs/superpowers/specs/2026-11-08-kadraj-design.md  # bu tasarımın kalıcı kopyası
```

## Özellik detayları

**Yakalama (alan/pencere/tam ekran)**
- Kısayolda önce tüm ekranlar `SCScreenshotManager.captureImage` ile dondurulur; her ekranda `.screenSaver` seviyesinde kenarlıksız overlay pencere açılır (CleanShot tarzı "freeze"). Alan seçimi: sürükle, boyut göstergesi, büyüteç, ok tuşlarıyla ince ayar, Space ile pencere moduna geçiş, Esc iptal.
- Pencere modu: `SCShareableContent.windows` üzerinden hover vurgusu; `SCContentFilter(desktopIndependentWindow:)` ile yakalama, gölge açık/kapalı ayarı.
- Çoklu ekran + Retina ölçeği doğru ele alınır.
- Yakalama sonrası: Quick Access küçük resmi (ayara göre otomatik kaydet/kopyala da olabilir). Kayıt yeri varsayılan `~/Desktop`, dosya adı şablonu `Kadraj 2026-11-08 at 14.03.22.png`.

**OCR + QR**
- Alan seç → `VNRecognizeTextRequest` (`.accurate`, diller `tr-TR, en-US` ayarlanabilir, satır sırası korunur) → panoya + bildirim. Editör ve Quick Access'ten de çalışır.
- QR/barkod: `VNDetectBarcodesRequest` → içerik panoya, URL ise "Aç" butonu.

**İşaretleme editörü**
- Araçlar: ok, dikdörtgen, elips, çizgi, kalem, vurgulayıcı, metin, numaralı adım rozeti, bulanıklaştır/mozaik (CIFilter), kırpma. Renk/kalınlık, geri al/yinele, seçip taşı/sil.
- Anotasyonlar `KadrajCore`'da değer tipleri; render CoreGraphics → test edilebilir. Çıkış: kopyala, kaydet, sürükle-bırak, pinle.

**Pinleme**
- Kenarlıksız `NSPanel` (`.floating`, tüm Space'lerde), sürüklenebilir, scroll/pinch ile zoom, opaklık, tıklama-geçirgen modu, çift tık/Esc ile kapanır, sağ tık menüsü (kopyala/kaydet/düzenle/OCR).

**Scroll capture (manuel)**
- Alan seç → HUD çıkar ("Kaydırın… Bitti / İptal"). `SCStream` (`sourceRect` = alan, ~15 fps, HUD ve overlay pencereleri `excludingWindows` ile hariç).
- Birleştirme (`KadrajCore/Stitching`): her karenin gri tonlamalı satır imzası (vImage) çıkarılır; önceki kareyle en iyi dikey örtüşme SAD ile bulunur; üstte/altta sabit kalan satırlar (yapışkan header/footer) tespit edilip tekrar eklenmez; sadece yeni satırlar eklenir. Değişim yoksa kare atlanır; ters kaydırma yok sayılır. Maks. yükseklik ~30.000 px.
- HUD'da canlı küçük önizleme. Sonuç normal yakalama akışına girer (Quick Access/editör).

**Ekran kaydı / GIF**
- Alan veya tam ekran → `SCStream` → `AVAssetWriter` H.264 `.mp4`; menü çubuğunda kayıt göstergesi + durdurma, isteğe bağlı tıklama vurgusu ve imleç gösterme.
- GIF: kayıt sonrası "GIF olarak dışa aktar" — `AVAssetImageGenerator` ile ~15 fps kare, küçültme, `CGImageDestination` (GIF). Ses v1'de yok.

**Renk seçici + cetvel**
- Renk: `NSColorSampler` → HEX panoya (ayardan RGB/HSL formatı).
- Cetvel: dondurulmuş ekran üzerinde iki nokta/dikdörtgen sürükle → px ve pt cinsinden genişlik/yükseklik/mesafe.

**İzin onboarding**
- İlk açılışta `CGPreflightScreenCaptureAccess`; yoksa açıklama penceresi + `CGRequestScreenCaptureAccess` + System Settings derin linki (`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`). İzin MDM ile engelliyse IT için README'de PPPC profil örneği (bundle id + Team ID).

**Güncelleme**
- Menüde "Güncellemeleri kontrol et": GitHub `releases/latest`; yeni sürüm varsa tek tıkla zip indir → SHA-256 doğrula → kendi `.app`'ini değiştir → yeniden başlat (uygulama kullanıcının yazabildiği yerde olduğu için admin'siz çalışır).

## Dağıtım

**`scripts/bundle.sh`**: `swift build -c release --arch arm64 --arch x86_64` → `Kadraj.app/Contents/{MacOS,Resources,Info.plist}` (SPM resource bundle'ı + icns kopyalanır) → `codesign --options runtime --timestamp -s "Developer ID Application: …"`; kimlik yoksa ad-hoc (`-s -`) imza (fork'lar için).

**`release.yml`** (tag `v*`): macos-14 runner → `swift test` → bundle → keychain'e p12 import (secret'lar: `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8`) → `notarytool submit --wait` → `stapler staple` → `ditto -c -k --keepParent` ile `Kadraj.zip` + `Kadraj.zip.sha256` → GitHub Release. Asset adı her sürümde sabit `Kadraj.zip`.
**`nightly.yml`**: main push → aynı build → `nightly` prerelease'i günceller. **`ci.yml`**: PR'da build + test + `shellcheck install.sh`.

**`install.sh`** (sadece macOS'ta hazır gelen araçlar: `curl`, `ditto`, `shasum`, `sw_vers`):
1. `set -euo pipefail`; argüman: boş → `latest`, `main` → `nightly`, diğer → baştaki `v` atılıp `v<ver>`.
2. macOS ≥ 14 kontrolü; değilse açık hata.
3. URL: `…/releases/latest/download/Kadraj.zip` veya `…/releases/download/<tag>/Kadraj.zip` (API kullanmaz → rate-limit yok). `.sha256` indirilip doğrulanır.
4. Hedef: `/Applications` yazılabilirse orası, değilse `~/Applications` (oluşturulur); `KADRAJ_INSTALL_DIR` ile override. **Hiçbir yerde sudo yok.**
5. Çalışan Kadraj kapatılır, geçici dizine açılır, eski `.app` atomik değiştirilir, `xattr -dr com.apple.quarantine` (zararsız güvence), uygulama açılır, izin hakkında kısa bilgi yazdırılır.
6. `KADRAJ_BASE_URL` env'i ile indirme kaynağı değiştirilebilir (lokal test için).
**`uninstall.sh`**: uygulamayı, `~/Library/Application Support/Kadraj`, tercihleri ve giriş öğesini siler.

**README** (TR + EN): kurulum komutları, özellik GIF'leri, izin/MDM bölümü, derleme talimatı.

## Uygulama sırası (her aşama kendi başına çalışır durumda biter)
0. **İskelet + dağıtım hattı**: repo, SPM, menü çubuğu uygulaması, izin onboarding, bundle/sign/notarize, workflow'lar, install/uninstall.sh → `v0.1.0` etiketiyle curl kurulumunu baştan sona doğrula. (Dağıtım en riskli kısım, en başta kanıtlanır.)
1. **Yakalama çekirdeği**: overlay, alan/pencere/tam ekran, çoklu ekran, Quick Access, kaydet/kopyala, hotkey'ler, ayarlar.
2. **OCR + QR**
3. **İşaretleme editörü**
4. **Pinleme**
5. **Scroll capture** (önce `Stitching` birim testleri, sonra UI)
6. **Ekran kaydı + GIF**
7. **Renk seçici + cetvel**
8. **Cila**: TR/EN yerelleştirme, ikon, self-update, giriş başlatma, README, `v1.0.0`.

Her aşama için uygulama sırasında superpowers:writing-plans ile ayrıntılı görev planı çıkarılır; çekirdek mantık TDD ile yazılır.

## Doğrulama
- `swift test`: stitching (sentetik kaydırılmış görüntüler, yapışkan header'lı vakalar), anotasyon render (piksel kontrolleri), dosya adı şablonu, sürüm karşılaştırma/argüman ayrıştırma.
- `shellcheck install.sh uninstall.sh`.
- Lokal kurulum testi: `python3 -m http.server` ile bundle'ı sun, `KADRAJ_BASE_URL=http://localhost:8000 bash install.sh 0.1.0`.
- **Kısıtlı Mac simülasyonu**: admin olmayan yeni bir standart kullanıcı hesabında curl kurulumu → `~/Applications`'a kurulduğunu, sudo istemediğini, Gatekeeper uyarısı çıkmadan açıldığını, izin akışını doğrula.
- İmza: `codesign --verify --deep --strict --verbose=2`, `spctl -a -vv Kadraj.app`, `xcrun stapler validate`.
- Gerçek release: `v0.1.0` etiketi → workflow → curl ile üç kurulum biçimi (`latest`, `0.1.0`, `main`).
- Her aşama sonunda manuel kontrol listesi (Retina + harici ekran, açık/koyu mod, farklı uygulamalarda scroll capture: Safari, Chrome, Notes, Terminal).
