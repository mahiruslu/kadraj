# Kadraj Faz 2 — OCR + QR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ekrandan alan seçip içindeki metni (Türkçe dahil, internetsiz) ya da QR/barkodu okuyup panoya kopyalamak; Quick Access'ten de mevcut yakalamanın metnini çıkarabilmek.

**Architecture:** Vision çağrıları ve satır birleştirme `KadrajCore`'da (gerçek Vision ile entegrasyon testleri: CoreText ile çizilmiş metin, CIQRCodeGenerator ile üretilmiş QR). Uygulama tarafında `CaptureCoordinator` iki yeni modu (`.text`, `.qr`) mevcut overlay ile alan seçip `RecognitionOutput`'a verir; sonuç bildirim izni gerektirmeyen kendi `ResultToast` panelimizle gösterilir.

**Tech Stack:** Vision (`VNRecognizeTextRequest` rev3, `VNDetectBarcodesRequest`), CoreText/CoreImage (testlerde), AppKit/SwiftUI.

**Spec:** `docs/superpowers/specs/2026-11-08-kadraj-design.md` (bölüm "OCR + QR")

## Global Constraints
- Tamamen offline; ağ çağrısı yok.
- Yeni izin yok: `UNUserNotificationCenter` kullanılmaz (bildirim izni ister) — sonuçlar kendi toast panelimizde.
- Kısayollar: `⌥⇧O` metin tanı (kVK O = 31), `⌥⇧Q` QR oku (kVK Q = 12); ayarlardan değiştirilebilir.
- Varsayılan OCR dilleri `["tr-TR", "en-US"]`; Vision'ın desteklemediği diller sessizce atlanır.
- Swift komutları `DEVELOPER_DIR=/Applications/Xcode-27.2.0.app/Contents/Developer` ile.

## Review Focus
1. Seçimde hiç metin/QR yok → panoya boş metin yazılmaz, toast "Metin bulunamadı" / "QR kod bulunamadı" der. *(Task 2 testleri: boş görüntü → `""` / `[]`; Task 4: boş sonuç yolu)*
2. Çok sütunlu / farklı yükseklikte satırlar → satırlar yukarıdan aşağı, aynı satırdaki parçalar soldan sağa birleşir. *(Task 1 testleri)*
3. Türkçe karakterler (ğüşıöç İ) doğru tanınır. *(Task 2: "Ağır Işık Güzel Şöyle Çiçek" entegrasyon testi)*
4. QR içeriği URL ise "Aç" butonu yalnızca http/https için gösterilir (`javascript:` / `file:` açılmaz). *(Task 1: `BarcodeAction.openableURL` testi)*
5. Eski ayar kaydı (faz 1) yeni kısayolları varsayılanlarla almalı. *(Task 3: decode testi)*

---

### Task 1: Core — satır birleştirme ve URL güvenliği

**Files:** Create `Sources/KadrajCore/Recognition/TextAssembler.swift`, `Sources/KadrajCore/Recognition/BarcodeAction.swift`; Tests `TextAssemblerTests.swift`, `BarcodeActionTests.swift`

**Interfaces (Produces):**
- `public struct RecognizedFragment: Equatable, Sendable { public let text: String; public let box: CGRect /* Vision normalize, sol-alt orijin */ }`
- `public enum TextAssembler { static func assemble(_ fragments: [RecognizedFragment]) -> String }` — dikey merkezleri, iki parçanın ortalama yüksekliğinin yarısından yakınsa aynı satır; satırlar `maxY` azalan sırada, satır içi `minX` artan, parçalar tek boşlukla, satırlar `\n` ile birleşir; boş parçalar atlanır.
- `public enum BarcodeAction { static func openableURL(_ payload: String) -> URL? }` — sadece `http`/`https` şemalı ve host'u olan URL.

- [ ] **Step 1: Failing tests** — iki satır ters sırada verilince yukarıdaki önce; aynı satırda sağdaki parça önce verilse de `"Merhaba Dünya"`; hafif kaymış (y farkı < yükseklik/2) parçalar aynı satır; boş girdi → `""`; `openableURL("https://kadraj.app/x")` non-nil, `"javascript:alert(1)"`, `"file:///etc/passwd"`, `"merhaba"` → nil.
- [ ] **Step 2–4:** FAIL → implement → PASS
- [ ] **Step 5:** Commit `feat(core): text line assembly and safe barcode URLs`

### Task 2: Core — Vision tanıyıcıları (entegrasyon testli)

**Files:** Create `Sources/KadrajCore/Recognition/TextRecognizer.swift`, `Sources/KadrajCore/Recognition/BarcodeReader.swift`; Tests `TextRecognizerTests.swift`, `BarcodeReaderTests.swift`

**Interfaces (Produces):**
- `public enum TextRecognizer { static func supportedLanguages() -> [String]; static func recognize(_ image: CGImage, languages: [String]) async throws -> String }` — `.accurate`, `usesLanguageCorrection = true`, desteklenmeyen diller filtrelenir (hepsi elenirse Vision varsayılanı), sonuç `TextAssembler` ile.
- `public struct BarcodeResult: Equatable, Sendable { public let payload: String; public let symbology: String }`; `public enum BarcodeReader { static func read(_ image: CGImage) async throws -> [BarcodeResult] }` — yinelenen payload'lar tekilleştirilir.

- [ ] **Step 1: Failing tests** — CoreText ile beyaz zemine 48 pt siyah metin çizen yardımcı; `"Merhaba Kadraj 2026"` → sonuç bu kelimeleri içerir; `"Ağır Işık Güzel Şöyle Çiçek"` (`tr-TR`) → sonuç (büyük/küçük harf duyarsız) `"ağır"`, `"ışık"`, `"güzel"`, `"şöyle"`, `"çiçek"` içerir; boş beyaz görüntü → `""`; `supportedLanguages()` `"tr-TR"` içerir; `CIQRCodeGenerator` ile `"https://github.com/mahiruslu/kadraj"` QR'ı (10× büyütülmüş, beyaz kenar boşluklu) → tek sonuç, payload eşit; boş görüntü → `[]`.
- [ ] **Step 2–4:** FAIL → implement (`VNImageRequestHandler(cgImage:)`, istek `perform` arka planda `Task.detached` ile) → PASS
- [ ] **Step 5:** Commit `feat(core): Vision text recognizer and barcode reader`

### Task 3: Core — yeni kısayollar ve OCR dil ayarı

**Files:** Modify `Sources/KadrajCore/Hotkeys/Hotkey.swift`, `Sources/KadrajCore/Settings/CaptureSettings.swift`; Tests `HotkeyTests.swift`, `CaptureSettingsTests.swift`

**Interfaces (Produces):**
- `HotkeyAction` yeni case'ler: `.recognizeText` ("Metin Tanı", `⌥⇧O`), `.readQRCode` ("QR Kod Oku", `⌥⇧Q`).
- `CaptureSettings.ocrLanguages: [String]`, varsayılan `["tr-TR", "en-US"]`, eksikse varsayılan.

- [ ] **Step 1: Failing tests** — `Hotkey.defaults[.recognizeText]?.displayString == "⌥⇧O"`, `.readQRCode` → `"⌥⇧Q"`, başlıklar; faz 1 biçimindeki JSON (`{"hotkeys":{"captureArea":{...}}}`) decode → yeni eylemlerin varsayılan kısayolları var, `ocrLanguages == ["tr-TR","en-US"]`.
- [ ] **Step 2–4:** FAIL → implement → PASS
- [ ] **Step 5:** Commit `feat(core): OCR/QR hotkeys and OCR language setting`

### Task 4: Uygulama — metin/QR modları, sonuç toast'u, menü ve URL

**Files:** Create `Sources/Kadraj/Recognition/ResultToast.swift`, `Sources/Kadraj/Recognition/RecognitionOutput.swift`; Modify `CaptureCoordinator.swift`, `SelectionOverlay*.swift` (ipucu metni), `StatusMenu.swift`, `AppDelegate.swift`

**Interfaces:**
- Consumes: Task 1–3.
- Produces:
  - `CaptureMode` yeni case'ler `.text`, `.qr` (URL: `kadraj://capture/text`, `kadraj://capture/qr`); overlay bu modlarda alan seçimi ile açılır (Space ile pencere modu da çalışır), ipucu "Metni okunacak alanı seçin" / "QR kodun bulunduğu alanı seçin".
  - `@MainActor final class ResultToastController { func show(title: String, detail: String?, actions: [ToastAction]) }`, `struct ToastAction { let title: String; let perform: () -> Void }` — ekranın üst ortasında, `.floating`, non-activating, 4 sn (üzerindeyken bekler), en fazla 1 tane (yenisi eskisini değiştirir).
  - `@MainActor enum RecognitionOutput { static func handleText(_ text: String, toast:); static func handleBarcodes(_ results: [BarcodeResult], toast:) }` — metin: boşsa "Metin bulunamadı"; değilse panoya `.string`, toast "Metin kopyalandı" + ilk 120 karakter önizleme. QR: boşsa "QR kod bulunamadı"; değilse ilk payload panoya, toast "QR kod okundu" + payload, `openableURL` varsa "Aç" aksiyonu, birden fazlaysa detayda "+N daha".
  - Menü: yakalama öğelerinin altına "Metin Tanı", "QR Kod Oku".
- [ ] **Step 1:** Yaz; `swift build` uyarısız, `swift test` PASS.
- [ ] **Step 2: Doğrula** — `scripts/dev.sh`; ekranda Türkçe metin içeren bir pencere (ör. README) üzerinde `⌥⇧O` ile alan seç → pano metni içerir (`pbpaste`), toast görünür; QR görüntüsü (ör. `qrencode` yoksa test yardımcısıyla üretilip Preview'da açılmış PNG) üzerinde `⌥⇧Q` → `pbpaste` URL'yi verir, toast'ta "Aç".
- [ ] **Step 3:** Commit `feat: text recognition and QR reading modes with result toast`

### Task 5: Quick Access "Metni Kopyala" + ayarlarda OCR dilleri

**Files:** Modify `Sources/Kadraj/QuickAccess/QuickAccessPanel.swift`, `Sources/Kadraj/Settings/SettingsWindow.swift`, `AppDelegate.swift`

**Interfaces:**
- Quick Access hover düğmelerine "Metni Kopyala" (`text.viewfinder`): `TextRecognizer` → `RecognitionOutput.handleText`.
- Ayarlar → yeni "Metin Tanıma" bölümü: `TextRecognizer.supportedLanguages()` listesinden çoklu seçim (Türkçe adlarla, `Locale.current.localizedString(forIdentifier:)`), en az bir dil zorunlu; sıra: seçilenler başta.
- [ ] **Step 1:** Yaz; build uyarısız, testler PASS.
- [ ] **Step 2: Doğrula** — yakalama sonrası Quick Access'te "Metni Kopyala" → pano metin; ayarlarda dil seçimi kalıcı.
- [ ] **Step 3:** Commit `feat: copy text from quick access and OCR language settings`

### Task 6: Dokümantasyon

**Files:** Modify `README.md`, `README.en.md`
- [ ] Kullanım tablosuna `⌥⇧O`, `⌥⇧Q`, `kadraj://capture/text|qr`; yol haritasında OCR/QR işaretli; tüm kontroller (`swift test`, kurulum/CI testleri, shellcheck, bundle) temiz; commit `docs: OCR and QR usage`.
