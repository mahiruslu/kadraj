# Kadraj Faz 1 — Yakalama Çekirdeği Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Alan / pencere / tam ekran görüntüsü alma; dondurulmuş ekran üzerinde seçim overlay'i, global kısayollar, Quick Access küçük resmi, kaydet/kopyala ve ayarlar penceresi.

**Architecture:** Saf geometri/isimlendirme/kodlama mantığı `KadrajCore`'da (Swift Testing ile TDD). Uygulama tarafında `CaptureCoordinator` akışı yönetir: `ScreenFreezer` (ScreenCaptureKit ile tüm ekranları dondur) → `SelectionOverlay` (ekran başına pencere; alan/pencere modu) → `CaptureOutput` (kaydet/kopyala/Quick Access). Kısayollar Carbon `RegisterEventHotKey` ile (Erişilebilirlik izni gerekmez). `kadraj://capture/<mode>` URL şeması otomasyon (Raycast/Alfred) ve uçtan uca doğrulama için.

**Tech Stack:** Swift 6, AppKit, SwiftUI (ayarlar), ScreenCaptureKit (`SCScreenshotManager`, macOS 14), Carbon HIToolbox, ImageIO, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-08-kadraj-design.md` (bölüm "Yakalama (alan/pencere/tam ekran)")

## Global Constraints
- Min macOS 14; Swift 6 strict concurrency, derleme uyarısız.
- Tek izin Ekran Kaydı; Erişilebilirlik / Input Monitoring kullanılmaz.
- Varsayılan kısayollar: `⌥⇧A` alan, `⌥⇧W` pencere, `⌥⇧F` tam ekran (scroll/OCR/kayıt/renk sonraki fazlarda).
- Dosya adı şablonu: `Kadraj 2026-11-08 at 14.03.22.png`; çakışmada ` (2)`, ` (3)` eklenir.
- Arayüz metinleri Türkçe.
- Swift komutları bu makinede `DEVELOPER_DIR=/Applications/Xcode-27.1.0.app/Contents/Developer` ile çalışır.
- AI atfı yok.

## Review Focus
1. Çoklu ekran + farklı ölçekler (Retina 2x + harici 1x): seçim doğru ekranın doğru piksellerini kırpmalı. *(Task 1: `pixelCropRect` 1x/2x testleri; Task 2: CG↔AppKit dönüşümü ikincil ekran testleri)*
2. Ekran Kaydı izni yokken kısayola basmak → çökme yok, onboarding açılır. *(Task 4 manuel kontrol + `CaptureCoordinator` izin kapısı)*
3. Kayıt klasörü yok / yazılamıyor → klasör oluşturulur; yazılamıyorsa görüntü yine panoya kopyalanır ve kullanıcıya hata gösterilir. *(Task 1: `uniqueURL`; Task 4: `CaptureOutput` hata yolu)*
4. Sıfır boyutlu / tek tık seçim → yakalama yapılmaz, overlay açık kalır (macOS davranışı gibi). *(Task 1: `isUsableSelection` testi)*
5. Kısayol başka uygulamayla çakışıyor / kaydedilemiyor → uygulama çalışmaya devam eder, ayarlarda "kullanılamıyor" gösterilir. *(Task 8: `HotkeyCenter.register` sonucu)*

---

### Task 1: Core — seçim geometrisi, dosya adı, görüntü kodlama

**Files:** Create `Sources/KadrajCore/Capture/SelectionGeometry.swift`, `Sources/KadrajCore/Export/FileNamer.swift`, `Sources/KadrajCore/Export/ImageEncoder.swift`; Tests `Tests/KadrajCoreTests/SelectionGeometryTests.swift`, `FileNamerTests.swift`, `ImageEncoderTests.swift`

**Interfaces (Produces):**
- `public enum SelectionGeometry`:
  - `static func normalizedRect(from: CGPoint, to: CGPoint) -> CGRect`
  - `static func isUsableSelection(_ r: CGRect) -> Bool` — genişlik ve yükseklik ≥ 2 pt
  - `static func pixelCropRect(selection: CGRect, screenSize: CGSize, scale: CGFloat) -> CGRect` — `selection` ekran-yerel AppKit noktaları (sol-alt orijin) → görüntü pikselleri (sol-üst orijin), `integral`, görüntü sınırına kırpılır
  - `static func nudge(_ r: CGRect, dx: CGFloat, dy: CGFloat, resize: Bool, within bounds: CGRect) -> CGRect` — resize=false taşır, true genişlik/yükseklik değiştirir (min 1), sonuç `bounds` içinde kalır
- `public enum FileNamer`:
  - `static func fileName(date: Date, ext: String, timeZone: TimeZone = .current) -> String`
  - `static func uniqueURL(directory: URL, fileName: String, exists: (URL) -> Bool) -> URL`
- `public enum ImageFormat: String, Codable, CaseIterable, Sendable { case png, jpeg }` + `var fileExtension: String` (`png`/`jpg`)
- `public enum ImageEncoder { static func data(for image: CGImage, format: ImageFormat, jpegQuality: Double = 0.9) -> Data? }`

- [ ] **Step 1: Failing tests**
```swift
@Test func normalizesReversedDrag() {
    #expect(SelectionGeometry.normalizedRect(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20))
            == CGRect(x: 10, y: 20, width: 40, height: 60))
}
@Test func tinySelectionIsNotUsable() {
    #expect(!SelectionGeometry.isUsableSelection(CGRect(x: 0, y: 0, width: 1, height: 50)))
    #expect(SelectionGeometry.isUsableSelection(CGRect(x: 0, y: 0, width: 2, height: 2)))
}
@Test func pixelCropFlipsAndScalesRetina() {
    // 1440x900 pt ekran, 2x: alt-soldaki 100x50 pt seçim, y=0
    let r = SelectionGeometry.pixelCropRect(selection: CGRect(x: 10, y: 0, width: 100, height: 50),
                                            screenSize: CGSize(width: 1440, height: 900), scale: 2)
    #expect(r == CGRect(x: 20, y: 1700, width: 200, height: 100))
}
@Test func pixelCropNonRetinaAndClamped() {
    let r = SelectionGeometry.pixelCropRect(selection: CGRect(x: -5, y: 880, width: 50, height: 40),
                                            screenSize: CGSize(width: 1920, height: 1080), scale: 1)
    #expect(r == CGRect(x: 0, y: 0, width: 45, height: 20))
}
@Test func nudgeMovesAndResizesWithinBounds() {
    let b = CGRect(x: 0, y: 0, width: 100, height: 100)
    let r = CGRect(x: 90, y: 10, width: 10, height: 10)
    #expect(SelectionGeometry.nudge(r, dx: 5, dy: 0, resize: false, within: b) == r)
    #expect(SelectionGeometry.nudge(r, dx: -1, dy: 1, resize: false, within: b) == CGRect(x: 89, y: 11, width: 10, height: 10))
    #expect(SelectionGeometry.nudge(r, dx: -20, dy: 0, resize: true, within: b).width == 1)
}
@Test func fileNameUsesTemplate() {
    var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 8; c.hour = 14; c.minute = 3; c.second = 22
    let tz = TimeZone(identifier: "Europe/Istanbul")!
    var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
    #expect(FileNamer.fileName(date: cal.date(from: c)!, ext: "png", timeZone: tz) == "Kadraj 2026-11-08 at 14.03.22.png")
}
@Test func uniqueURLAppendsCounter() {
    let dir = URL(fileURLWithPath: "/tmp/x")
    let taken: Set<String> = ["a.png", "a (2).png"]
    #expect(FileNamer.uniqueURL(directory: dir, fileName: "a.png") { taken.contains($0.lastPathComponent) }.lastPathComponent == "a (3).png")
    #expect(FileNamer.uniqueURL(directory: dir, fileName: "b.png") { _ in false }.lastPathComponent == "b.png")
}
@Test func encodesPNGAndJPEGRoundTrip() // 4x3 CGImage → data → CGImageSource ile geri: genişlik 4, yükseklik 3; png UTI public.png, jpeg public.jpeg
```
- [ ] **Step 2:** `swift test` → FAIL (tipler yok)
- [ ] **Step 3:** Implement. `fileName` için `DateFormatter` `en_US_POSIX`, `"yyyy-MM-dd 'at' HH.mm.ss"`. `ImageEncoder` `CGImageDestinationCreateWithData` + `kCGImageDestinationLossyCompressionQuality`.
- [ ] **Step 4:** `swift test` → PASS
- [ ] **Step 5:** Commit `feat(core): selection geometry, file naming and image encoding`

---

### Task 2: Core — ekran koordinatları, pencere isabet testi, kısayol modeli

**Files:** Create `Sources/KadrajCore/Capture/ScreenCoordinates.swift`, `Sources/KadrajCore/Capture/WindowHitTester.swift`, `Sources/KadrajCore/Hotkeys/Hotkey.swift`; Tests `ScreenCoordinatesTests.swift`, `WindowHitTesterTests.swift`, `HotkeyTests.swift`

**Interfaces (Produces):**
- `public enum ScreenCoordinates { static func appKitRect(fromCG r: CGRect, primaryScreenHeight h: CGFloat) -> CGRect }` — CG global (sol-üst, birincil ekran) → AppKit global (sol-alt): `y' = h - r.maxY`
- `public struct WindowCandidate: Equatable, Sendable { public let id: UInt32; public let frame: CGRect /* AppKit global */; public let layer: Int; public let ownerName: String; public init(...) }`
- `public enum WindowHitTester { static func topmost(at p: CGPoint, in candidates: [WindowCandidate]) -> WindowCandidate? }` — liste önden arkaya sıralı kabul edilir; sadece `layer == 0` ve genişlik/yükseklik ≥ 40
- `public enum HotkeyAction: String, Codable, CaseIterable, Sendable { case captureArea, captureWindow, captureFullscreen }` + `var title: String` ("Alan Yakala", "Pencere Yakala", "Tam Ekran Yakala")
- `public struct Hotkey: Codable, Equatable, Hashable, Sendable { public var keyCode: UInt32; public var modifiers: Modifiers }`, `public struct Modifiers: OptionSet, Codable, Hashable, Sendable { command, option, control, shift }` + `var carbonFlags: UInt32` (cmdKey 0x100, shiftKey 0x200, optionKey 0x800, controlKey 0x1000) + `var displayString: String` (Hotkey: sıra ⌃⌥⇧⌘ + tuş adı) + `static let defaults: [HotkeyAction: Hotkey]` (A=0, W=13, F=3 kVK kodları, `[.option, .shift]`)
- `public enum KeyNames { static func name(for keyCode: UInt32) -> String }` — harfler, rakamlar, F1–F12, Space, Return, Esc; bilinmeyen için `"Key \(code)"`

- [ ] **Step 1: Failing tests** — `appKitRect(fromCG: (100, 0, 200, 50), primaryScreenHeight: 900) == (100, 850, 200, 50)`; ikincil ekran üstte: `(0, -1080, 1920, 1080)` → `(0, 900, 1920, 1080)`; hit test: iç içe iki pencereden öndekini döndürür, layer≠0 (menü çubuğu) atlanır, 20x20 pencere atlanır, boşlukta `nil`; `Hotkey.defaults[.captureArea]!.displayString == "⌥⇧A"`; `Modifiers([.command, .shift]).carbonFlags == 0x300`; Hotkey JSON round-trip eşit; `KeyNames.name(for: 49) == "Space"`.
- [ ] **Step 2:** FAIL → **Step 3:** Implement → **Step 4:** PASS
- [ ] **Step 5:** Commit `feat(core): screen coordinates, window hit testing, hotkey model`

---

### Task 3: Core — yakalama ayarları

**Files:** Create `Sources/KadrajCore/Settings/CaptureSettings.swift`; Test `CaptureSettingsTests.swift`

**Interfaces (Produces):**
- `public struct CaptureSettings: Codable, Equatable, Sendable { saveDirectory: URL; format: ImageFormat; saveToFile: Bool; copyToClipboard: Bool; showQuickAccess: Bool; includeWindowShadow: Bool; showLoupe: Bool; hotkeys: [HotkeyAction: Hotkey] }`
  - `static func defaults(home: URL) -> CaptureSettings` — `saveDirectory = home/Pictures/Kadraj`, `.png`, üç çıkış da `true`, gölge `true`, büyüteç `true`, `Hotkey.defaults`
  - Decode eksik anahtarlarda varsayılana düşer (ileriki fazlarda alan eklenince eski kayıtlar bozulmasın).

- [ ] **Step 1: Failing tests** — varsayılan değerler; JSON round-trip; `{"format":"jpeg"}` decode → format jpeg, diğerleri varsayılan.
- [ ] **Step 2–4:** FAIL → implement (`init(from:)` içinde `decodeIfPresent ?? default`) → PASS
- [ ] **Step 5:** Commit `feat(core): capture settings with forward-compatible decoding`

---

### Task 4: Uygulama — kısayollar, menü, URL şeması, tam ekran yakalama ve çıktı

**Files:** Create `scripts/dev.sh`, `Sources/Kadraj/Hotkeys/HotkeyCenter.swift`, `Sources/Kadraj/Settings/SettingsStore.swift`, `Sources/Kadraj/Capture/ScreenFreezer.swift`, `Sources/Kadraj/Capture/CaptureCoordinator.swift`, `Sources/Kadraj/Capture/CaptureOutput.swift`; Modify `StatusMenu.swift`, `AppDelegate.swift`, `Resources/Info.plist`

**Interfaces:**
- Consumes: Task 1–3 tipleri.
- Produces:
  - `scripts/dev.sh` — sadece arm64 debug derler, `.app`'i `dist-dev/Kadraj.app` olarak paketler, `KADRAJ_SIGN_IDENTITY` (yoksa keychain'deki ilk "Apple Development" kimliği, o da yoksa ad-hoc) ile imzalar, çalışanı kapatıp açar. Sabit kimlikle imza sayesinde Ekran Kaydı izni yeniden derlemelerde korunur.
  - `@MainActor final class SettingsStore: ObservableObject { @Published var settings: CaptureSettings }` — UserDefaults `"captureSettings"` anahtarında JSON.
  - `@MainActor final class HotkeyCenter { func register(_ hotkeys: [HotkeyAction: Hotkey], handler: @escaping @MainActor (HotkeyAction) -> Void) -> [HotkeyAction: Bool] }` — önce tümünü kaldırır; dönen sözlük her eylem için kayıt başarılı mı.
  - `struct FrozenScreen { let screen: NSScreen; let image: CGImage; let scale: CGFloat }`; `enum ScreenFreezer { static func freezeAll() async throws -> [FrozenScreen] }` — `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`, `NSScreen`'i `CGDirectDisplayID` (`deviceDescription["NSScreenNumber"]`) ile `SCDisplay`'e eşler, `SCStreamConfiguration` genişlik/yükseklik = nokta × `backingScaleFactor`, `showsCursor = false`.
  - `@MainActor final class CaptureCoordinator { func start(_ mode: CaptureMode) }`, `enum CaptureMode: String { case area, window, fullscreen }` — izin yoksa onboarding; aynı anda tek yakalama; fullscreen: imlecin bulunduğu ekranın dondurulmuş görüntüsü doğrudan çıktıya.
  - `@MainActor enum CaptureOutput { static func deliver(_ image: CGImage, settings: CaptureSettings, quickAccess: (CGImage, URL?) -> Void) }` — panoya PNG; dosyaya `FileNamer` ile (klasörü oluşturur); kaydetme başarısızsa `NSAlert` yerine kullanıcı bildirimi değil, Quick Access'te hata metni (Task 7) — bu task'ta `NSLog` + panoya kopyalama garantisi.
  - Info.plist: `CFBundleURLTypes` → şema `kadraj`; `kadraj://capture/area|window|fullscreen` → `CaptureCoordinator.start`.
  - Menü: "Alan Yakala", "Pencere Yakala", "Tam Ekran Yakala" (kısayol gösterimiyle), ayraç, "Ayarlar…" (⌘,), mevcut öğeler.
- [ ] **Step 1:** Yaz, `swift build` uyarısız, `swift test` PASS.
- [ ] **Step 2: Doğrula** — `scripts/dev.sh`; izin verilmişken `open "kadraj://capture/fullscreen"` → `~/Pictures/Kadraj/Kadraj … .png` oluşur, boyutu ana ekranın piksel boyutuna eşit (`sips -g pixelWidth -g pixelHeight`), pano görüntü içerir (`osascript -e 'clipboard info'` → `«class PNGf»`). `⌥⇧F` aynı sonucu verir.
- [ ] **Step 3:** Commit `feat: hotkeys, URL scheme and full-screen capture`

---

### Task 5: Alan seçimi overlay'i

**Files:** Create `Sources/Kadraj/Capture/SelectionOverlayWindow.swift`, `Sources/Kadraj/Capture/SelectionOverlayView.swift`, `Sources/Kadraj/Capture/Loupe.swift`; Modify `CaptureCoordinator.swift`

**Interfaces:**
- Consumes: `FrozenScreen`, `SelectionGeometry`.
- Produces: `@MainActor final class SelectionOverlayController { init(frozen: [FrozenScreen], mode: CaptureMode, settings: CaptureSettings, windows: [WindowCandidate]); func run(completion: @escaping @MainActor (CGImage?) -> Void) }` — her ekrana borderless `NSPanel` (level `.screenSaver`, `canBecomeKey`, tüm Space'ler), arka planda dondurulmuş görüntü + %40 karartma, seçim deliği, kenarda `"W × H"` piksel etiketi, artı imleç; büyüteç (ayar açıksa) imleç yanında 8× büyütülmüş 15×15 piksel + koordinat; sürükle-bırak bitince seçim kullanılabilirse yakalar; ok tuşları 1 pt (⇧ ile 10 pt) taşır, ⌥+ok boyutlandırır, Return onaylar, Esc iptal eder (completion nil); seçim başladığı ekranla sınırlı.
- [ ] **Step 1:** Yaz; `swift build` uyarısız.
- [ ] **Step 2: Doğrula (manuel)** — `⌥⇧A`: ekran donar, sürükle → etiket doğru piksel boyutu, bırak → dosya kırpılmış ve boyutu etiketteki ile aynı; Esc iptal eder ve dosya oluşmaz; tek tık bir şey yakalamaz; harici ekranda da doğru bölge.
- [ ] **Step 3:** Commit `feat: area selection overlay with loupe and keyboard nudging`

---

### Task 6: Pencere modu

**Files:** Create `Sources/Kadraj/Capture/WindowCapturer.swift`; Modify overlay dosyaları, `CaptureCoordinator.swift`

**Interfaces:**
- Produces: `enum WindowCapturer { static func candidates() async throws -> ([WindowCandidate], [CGWindowID: SCWindow]); static func capture(_ window: SCWindow, includeShadow: Bool) async throws -> CGImage }` — kendi pencerelerini hariç tutar; `SCContentFilter(desktopIndependentWindow:)`, `config.ignoreShadowsSingleWindow = !includeShadow`, boyut `filter.contentRect.size × filter.pointPixelScale`.
- Overlay: pencere modunda imlecin altındaki pencere (`WindowHitTester`) mavi çerçeveyle vurgulanır, tıklayınca o pencere yakalanır. Alan modunda Space → pencere moduna geçer (ve geri).
- [ ] **Step 1:** Yaz; `swift build` uyarısız.
- [ ] **Step 2: Doğrula** — `⌥⇧W` ile bir Finder penceresi: gölge ayarı açıkken saydam kenarlı gölgeli PNG, kapalıyken tam pencere boyutu; `kadraj://capture/window` aynı akışı açar.
- [ ] **Step 3:** Commit `feat: window capture mode with shadow option`

---

### Task 7: Quick Access paneli

**Files:** Create `Sources/Kadraj/QuickAccess/QuickAccessPanel.swift`; Modify `CaptureOutput.swift`, `CaptureCoordinator.swift`

**Interfaces:**
- Produces: `@MainActor final class QuickAccessController { func show(image: CGImage, fileURL: URL?, error: String?) }` — ekranın sağ altında (imlecin bulunduğu ekran) `NSPanel` (`.floating`, non-activating), 220 pt genişlikte küçük resim; üzerine gelince düğmeler: "Kopyala", "Kaydet…" (`NSSavePanel`), "Finder'da Göster" (dosya varsa), "Kapat"; küçük resim dosya olarak sürüklenebilir (dosya yoksa geçici PNG yazılır); fare üzerinde değilse 8 sn sonra kaybolur; yeni yakalama gelince üstüne yığılır (en fazla 3). `error` varsa kırmızı metin.
- [ ] **Step 1:** Yaz; `swift build` uyarısız.
- [ ] **Step 2: Doğrula** — yakalama sonrası panel görünür, Kopyala/Kaydet/Göster çalışır, Finder'a sürükleyince dosya oluşur, 8 sn sonra kaybolur; kayıt klasörü yazılamaz yapılınca (`chmod 500`) panel hata metni gösterir ve pano yine dolu.
- [ ] **Step 3:** Commit `feat: quick access panel after capture`

---

### Task 8: Ayarlar penceresi + kısayol kaydedici

**Files:** Create `Sources/Kadraj/Settings/SettingsWindow.swift`, `Sources/Kadraj/Settings/ShortcutRecorder.swift`; Modify `AppDelegate.swift`

**Interfaces:**
- Produces: SwiftUI ayarlar (NSWindow içinde, menüden açılır): **Genel** — kayıt klasörü (Değiştir… `NSOpenPanel`), biçim PNG/JPEG, "Dosyaya kaydet", "Panoya kopyala", "Quick Access göster", "Pencere gölgesini dahil et", "Büyüteci göster"; **Kısayollar** — her `HotkeyAction` için kaydedici (tıkla → tuş kombinasyonuna bas; en az bir değiştirici zorunlu; Esc iptal, ⌫ temizler) ve `HotkeyCenter.register` başarısızsa "Bu kısayol kullanılamıyor" uyarısı. Değişiklik anında kaydedilir ve kısayollar yeniden kaydedilir.
- [ ] **Step 1:** Yaz; `swift build` uyarısız, `swift test` PASS.
- [ ] **Step 2: Doğrula** — klasörü değiştir → yeni yakalama oraya gider; JPEG seç → `.jpg`; alan kısayolunu `⌃⇧2` yap → eski kısayol çalışmaz, yenisi çalışır; uygulamayı yeniden başlat → ayarlar korunur.
- [ ] **Step 3:** Commit `feat: settings window with shortcut recorder`

---

### Task 9: Dokümantasyon ve son doğrulama

**Files:** Modify `README.md`, `README.en.md`

- [ ] **Step 1:** Yol haritasında yakalama maddesini işaretle; "Kullanım" bölümü (kısayollar, `kadraj://capture/area|window|fullscreen`, Quick Access); "Geliştirme" bölümüne `scripts/dev.sh` ve Xcode ile açma (`xed .`).
- [ ] **Step 2:** `swift test`, `/bin/bash Tests/install_test.sh`, `shellcheck`, `scripts/bundle.sh` → hepsi temiz.
- [ ] **Step 3:** Commit `docs: capture usage and development workflow`
