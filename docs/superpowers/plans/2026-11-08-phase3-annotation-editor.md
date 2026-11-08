# Kadraj Faz 3 — İşaretleme Editörü Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Yakalanan görüntü üzerinde ok, çizgi, dikdörtgen, elips, kalem, vurgulayıcı, metin, numaralı adım, bulanıklaştır/mozaik ve kırpma ile işaretleme; geri al/yinele, seç-taşı-sil; kopyala/kaydet.

**Architecture:** Belge modeli, geometri, isabet testi ve **render** `KadrajCore`'da (CoreGraphics + CoreImage, piksel testli). Uygulama tarafında `EditorWindowController` (NSWindow) + SwiftUI araç çubuğu + `AnnotationCanvasView` (NSView; aynı `AnnotationRenderer` çizim fonksiyonlarını görünüm ölçeğinde kullanır). Editör Quick Access'teki "Düzenle" düğmesi veya küçük resme çift tıklama ile açılır.

**Tech Stack:** CoreGraphics, CoreImage (`CIPixellate`, `CIGaussianBlur`), CoreText, AppKit, SwiftUI, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-08-kadraj-design.md` (bölüm "İşaretleme editörü")

## Global Constraints
- Anotasyon koordinatları **görüntü pikseli, sol-üst orijin** (ekran/yakalama ile aynı); çizimde tek bir flip dönüşümüyle CG'ye çevrilir.
- Anotasyonlar değer tipleri; geri al/yinele belge anlık görüntüsü (snapshot) ile, sınır 100 adım.
- Renk paleti: kırmızı `#FF3B30`, turuncu `#FF9500`, sarı `#FFCC00`, yeşil `#34C759`, mavi `#007AFF`, siyah `#000000`, beyaz `#FFFFFF`; kalınlık S/M/L = 3/6/10 px (görüntü pikseli, Retina'da ×scale değil — görüntü piksel uzayında sabit).
- Varsayılan araç ok, renk kırmızı, kalınlık M.
- Arayüz Türkçe; kısayollar: V seç, A ok, L çizgi, R dikdörtgen, O elips, P kalem, H vurgulayıcı, T metin, N adım, B bulanıklaştır, M mozaik, C kırp; ⌘Z/⇧⌘Z; ⌫ seçiliyi sil; ⌘C kopyala; ⌘S kaydet; Esc seçimi bırak.
- Swift komutları `DEVELOPER_DIR=/Applications/Xcode-27.2.0.app/Contents/Developer` ile.

## Review Focus
1. Kırpma + bulanıklaştırma birlikte: kırpılmış sonuçta bulanık bölge doğru yerde kalmalı. *(Task 3: `cropKeepsPixelatedRegionAligned`)*
2. Görüntü dışına taşan anotasyon (ok ucu kenarda, bulanık alan yarısı dışarıda) → çökme yok, sonuç görüntü boyutunda. *(Task 3: taşan alan testi)*
3. Geri al → yinele → yeni işlem: yinele yığını temizlenir. *(Task 1 testi)*
4. Adım numaraları: 1,2,3 eklenip 2 silinince sonraki adım 4 olur (mevcut en büyük + 1), numaralar kendiliğinden kaymaz. *(Task 1 testi)*
5. Editör açıkken aynı yakalama için tekrar "Düzenle" → ikinci pencere açılmaz, mevcut öne gelir. *(Task 6 manuel kontrol)*

---

### Task 1: Core — belge modeli, geri al/yinele, adım numarası

**Files:** Create `Sources/KadrajCore/Annotation/Annotation.swift`, `Sources/KadrajCore/Annotation/AnnotationDocument.swift`; Test `AnnotationDocumentTests.swift`

**Interfaces (Produces):**
- `public struct RGBAColor: Codable, Hashable, Sendable { r, g, b, a: Double; static let red, orange, yellow, green, blue, black, white; static let palette: [RGBAColor]; var cgColor: CGColor }`
- `public enum StrokeWidth: CGFloat, CaseIterable, Sendable { case small = 3, medium = 6, large = 10 }`
- `public struct AnnotationStyle: Equatable, Sendable { var color: RGBAColor; var width: StrokeWidth }`
- `public enum AnnotationKind: Equatable, Sendable { case arrow(CGPoint, CGPoint), line(CGPoint, CGPoint), rectangle(CGRect), ellipse(CGRect), pen([CGPoint]), highlighter([CGPoint]), text(origin: CGPoint, string: String, fontSize: CGFloat), step(center: CGPoint, number: Int), pixelate(CGRect), blur(CGRect) }`
- `public struct Annotation: Identifiable, Equatable, Sendable { let id: UUID; var kind: AnnotationKind; var style: AnnotationStyle; func translated(dx: CGFloat, dy: CGFloat) -> Annotation }`
- `public struct AnnotationDocument: Equatable, Sendable { let imageSize: CGSize; var annotations: [Annotation]; var crop: CGRect? ; var nextStepNumber: Int /* max mevcut step + 1, yoksa 1 */ }`
- `public struct EditHistory: Sendable { init(_ doc: AnnotationDocument); var current: AnnotationDocument { get }; var canUndo/canRedo: Bool; mutating func apply(_ change: (inout AnnotationDocument) -> Void); mutating func undo(); mutating func redo() }` — `apply` yinele yığınını temizler, geçmiş 100 ile sınırlı.

- [ ] **Step 1: Failing tests** — `apply` ekle → `undo` → boş → `redo` → geri gelir; undo sonrası yeni `apply` → `canRedo == false`; 101 `apply` sonrası 100 kez undo mümkün, 101. değil; step 1,2,3 ekle, 2'yi sil → `nextStepNumber == 4`; boş belgede `1`; `translated` dikdörtgeni ve kalem noktalarını kaydırır; palette 7 renk ve ilk kırmızı.
- [ ] **Step 2–4:** FAIL → implement → PASS
- [ ] **Step 5:** Commit `feat(core): annotation document model with undo history`

### Task 2: Core — geometri ve isabet testi

**Files:** Create `Sources/KadrajCore/Annotation/AnnotationGeometry.swift`; Test `AnnotationGeometryTests.swift`

**Interfaces (Produces):**
- `public enum AnnotationGeometry`:
  - `static func arrowHead(from: CGPoint, to: CGPoint, width: CGFloat) -> (left: CGPoint, tip: CGPoint, right: CGPoint)` — uç uzunluğu `max(width * 4, 16)`, açı ±28°.
  - `static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat`
  - `static func bounds(of kind: AnnotationKind, width: CGFloat) -> CGRect` (metin için yaklaşık: `fontSize * 0.6 * karakter` × `fontSize * 1.3`)
  - `static func hitTest(_ p: CGPoint, annotations: [Annotation], tolerance: CGFloat = 8) -> UUID?` — üstteki (dizinin sonundaki) önce; çizgi/ok/kalem için segment uzaklığı ≤ tolerans + width/2; dikdörtgen/elips yalnız kenar çevresinde (içi boş, tıklanınca alttakini seçebilmek için); metin/adım/bulanık/mozaik için bounds içi.
- [ ] **Step 1: Failing tests** — yatay ok `(0,0)→(100,0)` w=6: tip `(100,0)`, sol/sağ x < 100 ve y simetrik; segment uzaklığı (orta nokta 0, dik 5); hitTest: çizgi üzerinde nokta → id, 30 px uzakta → nil; dikdörtgen kenarı → id, tam ortası → nil; üst üste iki anotasyonda sonuncusu döner; step bounds merkezde.
- [ ] **Step 2–4:** FAIL → implement → PASS
- [ ] **Step 5:** Commit `feat(core): annotation geometry and hit testing`

### Task 3: Core — renderer

**Files:** Create `Sources/KadrajCore/Annotation/AnnotationRenderer.swift`; Test `AnnotationRendererTests.swift`

**Interfaces (Produces):**
- `public enum AnnotationRenderer`:
  - `static func render(base: CGImage, document: AnnotationDocument) -> CGImage?` — tam çözünürlük: taban → pixelate/blur bölgeleri (CoreImage, taban görüntüden örneklenir, bölge görüntüye kırpılır) → diğer anotasyonlar sırayla → `crop` varsa kırpılır.
  - `static func draw(_ annotation: Annotation, in ctx: CGContext, base: CGImage?, imageHeight: CGFloat)` — uygulamanın kanvası da bunu kullanır (ctx görüntü piksel uzayına dönüştürülmüş olarak verilir; flip içeride).
  - Stiller: ok/çizgi yuvarlak uçlu, ok ucu dolu üçgen; dikdörtgen/elips kontur; kalem yuvarlak birleşimli yol; vurgulayıcı renk %35 opak, kalınlık ×3, `multiply` karışım; metin CoreText kalın sistem fontu, beyaz kontur ile okunaklı; adım: dolu daire (çap `max(width*5, 28)`), ortada beyaz kalın numara; pixelate `CIPixellate` scale = `max(rect.minDim / 12, 8)`; blur `CIGaussianBlur` radius 12.
- [ ] **Step 1: Failing tests** — 200×100 beyaz taban: kırmızı dikdörtgen (10,10,80,40) w=6 → kenar pikseli (10,30) kırmızıya yakın, merkez (50,30) beyaz; pixelate testi: dama tahtası taban, (0,0,100,100) pixelate → bölge içi komşu pikseller eşit, dışı değişmemiş; `crop (50,0,100,100)` → sonuç 100×100; `cropKeepsPixelatedRegionAligned`: pixelate (60,10,40,40) + crop (50,0,100,100) → sonuçta (10…50, 10…50) bloklu, (60,60) orijinal; taşan blur (180,80,100,100) → çökme yok, 200×100; metin "Kadraj" → beyaz olmayan piksel sayısı > 0; adım 3 → merkez pikseli daire rengi değil (numara beyaz) ve kenarı daire rengi.
- [ ] **Step 2–4:** FAIL → implement → PASS
- [ ] **Step 5:** Commit `feat(core): annotation renderer with pixelate, blur and crop`

### Task 4: Uygulama — editör penceresi, kanvas, şekil araçları

**Files:** Create `Sources/Kadraj/Editor/EditorWindowController.swift`, `Sources/Kadraj/Editor/EditorModel.swift`, `Sources/Kadraj/Editor/AnnotationCanvasView.swift`, `Sources/Kadraj/Editor/EditorToolbar.swift`

**Interfaces:**
- Consumes: Task 1–3.
- Produces:
  - `enum EditorTool: String, CaseIterable { case select, arrow, line, rectangle, ellipse, pen, highlighter, text, step, blur, pixelate, crop }` + Türkçe `title`, SF Symbol `symbol`, `shortcut` (Global Constraints'teki harfler).
  - `@MainActor final class EditorModel: ObservableObject { @Published var history: EditHistory; @Published var tool: EditorTool; @Published var style: AnnotationStyle; @Published var selection: UUID?; let base: CGImage; let sourceURL: URL?; func render() -> CGImage? }`
  - `AnnotationCanvasView: NSView` — görüntüyü pencereye sığacak ölçekte ortalar (`imageToView` dönüşümü), `AnnotationRenderer.draw` ile çizer; sürükle ile şekil oluşturur (sürüklerken geçici anotasyon, bırakınca `history.apply`); `select` aracında tıkla → `hitTest`, sürükle → `translated`, ⌫ siler, seçili anotasyonun bounds'unu kesikli çizer; ⇧ ile çizgi/ok 45° katlarına, dikdörtgen/elips kareye kilitlenir.
  - `EditorToolbar` (SwiftUI): araç düğmeleri, 7 renk, S/M/L, geri al/yinele, sağda Kopyala / Kaydet.
  - `@MainActor final class EditorWindowController { static func open(image: CGImage, sourceURL: URL?) }` — aynı `sourceURL` için açık pencere varsa öne getirir; pencere boyutu ekranın %80'ini geçmez; başlık dosya adı ya da "Yeni Yakalama".
- [ ] **Step 1:** Yaz; build uyarısız.
- [ ] **Step 2: Doğrula** — Task 6'dan önce geçici olarak `kadraj://edit-last` yerine doğrudan test: Quick Access bağlantısı Task 6'da; bu task'ta `EditorWindowController.open` bir test görüntüsüyle `kadraj://editor-test` (DEBUG derlemede) ile açılır; ok/dikdörtgen/kalem çiz, seç-taşı-sil, ⌘Z/⇧⌘Z çalışır (sentetik girdi + ekran görüntüsü).
- [ ] **Step 3:** Commit `feat: annotation editor window with shape tools`

### Task 5: Metin, adım, bulanıklaştır/mozaik, kırpma araçları

**Files:** Modify `AnnotationCanvasView.swift`, `EditorModel.swift`

- Metin: tıklanan yere `NSTextField` (kenarlıksız, seçili renk, font 24 px × görüntü/görünüm ölçeği) yerleşir; Return/odak kaybı → anotasyon, Esc iptal; seçili metne çift tık → düzenle.
- Adım: tıklama → `.step(center, number: history.current.nextStepNumber)`.
- Bulanık/mozaik: sürükle → dikdörtgen.
- Kırp: sürükle → `document.crop` (geri alınabilir), kırpma dışı karartılır, Return onaylar / Esc iptal eder.
- [ ] **Step 1:** Yaz; build uyarısız. **Step 2: Doğrula** — her araçla çizip ekran görüntüsü; metin yaz → görünür; adımlar 1,2,3; bulanık bölge okunmaz; kırp → Kopyala sonucu kırpılmış boyutta (`osascript -e 'clipboard info'` / `pbpaste` görüntü boyutu ile).
- [ ] **Step 3:** Commit `feat: text, step, blur, pixelate and crop tools`

### Task 6: Çıktılar ve Quick Access bağlantısı

**Files:** Modify `EditorModel.swift`, `EditorToolbar.swift`, `QuickAccessPanel.swift`, `AppDelegate.swift`

- Kopyala (⌘C): `render()` → `CaptureOutput.copyToClipboard`.
- Kaydet (⌘S): `sourceURL` varsa üzerine yazar (aynı biçimde), yoksa `CaptureOutput.save` ile ayarlardaki klasöre; "Farklı Kaydet…" (⇧⌘S) `NSSavePanel`.
- Kapatırken kaydedilmemiş değişiklik varsa "Değişiklikleri kaydet?" (Kaydet / Kaydetme / İptal).
- Quick Access: hover düğmelerine "Düzenle" (`pencil.tip.crop.circle`); küçük resme çift tık artık editörü açar (eskiden dosyayı açıyordu).
- [ ] **Step 1:** Yaz; build uyarısız, testler PASS. **Step 2: Doğrula** — yakala → Quick Access "Düzenle" → ok çiz → ⌘S → dosya güncellendi (boyut/değişim zamanı) ve içerikte kırmızı pikseller; aynı küçük resimden tekrar "Düzenle" → yeni pencere açılmaz.
- [ ] **Step 3:** Commit `feat: editor output and quick access integration`

### Task 7: Dokümantasyon
- [ ] README (TR/EN): editör bölümü (araçlar ve kısayollar), yol haritasında işaretleme editörü işaretli; tüm kontroller temiz; commit `docs: annotation editor`.
