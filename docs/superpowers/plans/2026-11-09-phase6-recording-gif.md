# Kadraj Faz 6 — Ekran Kaydı + GIF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Seçili alanı veya ekranı H.264 MP4 olarak kaydetmek; kaydı GIF'e dönüştürmek.

**Architecture:** Core: `RecordingGeometry.evenPixelSize`, `GIFTiming.frameTimes`, `GIFEncoder.encode` (ImageIO) — test edilir. Uygulama: `RecordingSession` (SCStream → AVAssetWriter, seri kuyruk), menü çubuğu kayıt göstergesi, bitince sonuç toast'u (Aç / Finder'da Göster / GIF olarak dışa aktar), `GIFExporter` (AVAssetImageGenerator, 15 fps, en fazla 800 px genişlik, en fazla 600 kare).

**Spec:** `docs/superpowers/specs/2026-11-08-kadraj-design.md` (bölüm "Ekran kaydı / GIF")

## Global Constraints
- Kısayol `⌥⇧R` (kVK R = 15) başlatır; kayıt sürerken aynı kısayol / menü "Kaydı Durdur" bitirir. URL `kadraj://capture/record`.
- Alan seçiminde sürüklemeden tıklama → imlecin bulunduğu ekranın tamamı; Space → pencere çerçevesi.
- 30 fps, imleç görünür, ses yok (v1). Dosya: kayıt klasörü, `Kadraj Kayıt 2026-11-09 at 01.02.03.mp4`.
- Video boyutu piksel cinsinden çift sayı (H.264).
- Tıklama vurgusu v1'de yok (spec'te isteğe bağlı).

## Review Focus
1. Tek sayılı / küçük boyutlar → çift ve ≥ 2. *(Task 1 testi)*
2. Çok kısa kayıt (0–1 kare) → hata mesajı, bozuk dosya bırakılmaz. *(Task 2)*
3. Uzun kayıt GIF'i → 600 kare sınırı, süre korunur (gecikme ayarlanır). *(Task 1 testi)*
4. Kayıt sürerken başka yakalama başlatılamaz. *(Task 2)*

### Task 1: Core
- [ ] Tests: `evenPixelSize(CGSize(width: 101.5, height: 50.25), scale: 2) == (202, 100)`, `(0.4, 0.4) scale 1 → (2, 2)`; `frameTimes(duration: 2, fps: 15, maxFrames: 600)` 30 değer, ilk 0, adım 1/15; `duration 100` → 600 değer, son < 100, `delay` = 100/600; `GIFEncoder.encode([kırmızı, mavi 10×10], delay: 0.1)` → CGImageSource tipi `com.compuserve.gif`, 2 kare, gecikme 0.1, döngü 0 (sonsuz).
- [ ] Implement → PASS → commit `feat(core): recording size, GIF timing and encoder`.

### Task 2: Uygulama
- [ ] `HotkeyAction.recordScreen` ("Ekranı Kaydet", `⌥⇧R`) + test; `CaptureMode.record`; `RecordingSession`; menü göstergesi; sonuç toast'u; `GIFExporter`; README. Doğrula: `kadraj://capture/record` + sentetik sürükleme → 3 sn → `kadraj://capture/record` (durdur) → MP4 oluşur, `AVAsset` süresi ≈ 3 sn, boyutu seçimle eşleşir; GIF dışa aktar → GIF dosyası > 1 kare. Commit `feat: screen recording and GIF export`.
