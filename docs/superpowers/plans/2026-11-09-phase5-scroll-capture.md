# Kadraj Faz 5 — Kaydırarak Yakalama Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Kullanıcı seçtiği alanın altındaki içeriği kendisi kaydırırken kareleri toplayıp tek uzun görüntüde birleştirmek.

**Architecture:** `KadrajCore/Stitching/ScrollStitcher` (saf, test edilir): kare başına gri satır imzaları; önceki kareyle üst/alt sabit bölgeler (sticky header/footer) bulunur, ortadaki kayan bölgede SAD ile en iyi dikey kaydırma aranır (önce her 4. satırla kaba, sonra ±4 ince), yalnız yeni açığa çıkan satırlar eklenir. Uygulamada `ScrollSession`: alan seçimi → `SCStream` (sourceRect = alan, ~15 fps, Kadraj pencereleri hariç) → kareler seri kuyrukta stitcher'a → HUD'da yükseklik / "daha yavaş kaydırın" uyarısı → Bitti ile çıktı akışına.

**Spec:** `docs/superpowers/specs/2026-11-08-kadraj-design.md` (bölüm "Scroll capture (manuel)")

## Global Constraints
- Manuel kaydırma; Erişilebilirlik izni yok. Ters yön (yukarı) kaydırma yok sayılır.
- En fazla 30.000 piksel yükseklik; aşılınca otomatik biter.
- Kısayol `⌥⇧S` (kVK S = 1), menü "Kaydırarak Yakala", URL `kadraj://capture/scroll`.
- HUD ve seçim çerçevesi yakalamaya girmez (uygulama pencereleri hariç tutulur); çerçeve tıklamaları geçirir ki alttaki içerik kaydırılabilsin.

## Review Focus
1. Sabit header/footer tekrar etmez. *(Task 1 testi)*
2. Hiç kaydırılmayan kare → değişiklik yok; ters kaydırma → eklenmez. *(Task 1 testleri)*
3. Çok hızlı kaydırma (örtüşme yok) → eşleşme yok uyarısı, yanlış birleştirme yapılmaz. *(Task 1 testi)*
4. Değişken kaydırma miktarları doğru birleşir (piksel karşılaştırmalı). *(Task 1 testi)*
5. Yükseklik sınırı. *(Task 1 testi)*

### Task 1: Core — ScrollStitcher
**Files:** Create `Sources/KadrajCore/Stitching/ScrollStitcher.swift`; Test `ScrollStitcherTests.swift`
- `public final class ScrollStitcher { public enum AddResult: Equatable { case first, appended(Int), unchanged, noMatch, limitReached }; public init(maxHeight: Int = 30_000); public func add(_ frame: CGImage) -> AddResult; public var height: Int { get }; public func image() -> CGImage? }`
- [ ] Failing tests (gürültülü desenli 300×2400 uzun görüntüden 400 px'lik pencereler): 0/130/300/420 kaydırmalı kareler → sonuç uzun görüntünün 0…820 bölgesine piksel piksel eşit; 40 px header + 30 px footer sabit karelerde sonuç = header + içerik + footer (header bir kez); aynı kare iki kez → `.unchanged`; geri kaydırma → `.noMatch` ve yükseklik değişmez; 390 px atlama (örtüşme < %25) → `.noMatch`; `maxHeight: 900` → sınırı geçen ekleme `.limitReached`, yükseklik ≤ 900.
- [ ] implement → PASS → commit `feat(core): scroll capture stitcher`.

### Task 2: Uygulama — kaydırma oturumu
**Files:** Create `Sources/Kadraj/Scroll/ScrollSession.swift`, `Sources/Kadraj/Scroll/ScrollHUD.swift`; Modify `CaptureCoordinator.swift`, `Hotkey.swift` (+ test), `StatusMenu.swift`, `AppDelegate.swift`, overlay ipucu
- [ ] Yaz; build uyarısız; `HotkeyAction.scrollCapture` ("Kaydırarak Yakala", `⌥⇧S`) testi. Doğrula: uzun bir görüntüyü Preview'da açıp `kadraj://capture/scroll` + sentetik kaydırma ile uzun PNG oluştuğunu ve yüksekliğinin pencereden büyük olduğunu, içerikte tekrar olmadığını (ekran görüntüsüyle) kontrol et. README. Commit `feat: scrolling capture`.
